//
// (C) Copyright Tilo Prütz
//

#include "TUnit/TObject.Mock.h"

#pragma .h #include <TFoundation/TFoundation.h>

#include <objc/runtime.h>

#include "TUnit/TTestException.h"
#include "TUnit/TMockMessage.h"


#pragma .h #define shouldReceive shouldReceiveAt: __FILE__ : __LINE__
#pragma .h #define shouldNotReceive shouldNotReceiveAt: __FILE__ : __LINE__

#pragma .h void verifyAndCleanupMocks();


extern void __objc_update_dispatch_table_for_class(Class);
extern void __objc_install_premature_dtable(Class);


@implementation TObject(Mock)


typedef struct __TCDictionary {
    unsigned int tableSize;
    unsigned int count;
    _TLinkedTable **lists;
} _TCDictionary;


typedef struct __TMockData {
    BOOL rcvIsClass;
    Class originalClass;
    Class replayerClass;
    BOOL isRecording;
    TMutableArray *messages;
    BOOL totallyReplaceMethod;
    int callCount;
    TMutableSet *totallyReplacedMethods;
    const char *file;
    int line;
} _TMockData;


static _TLinkedTable *__lookup(_TCDictionary *dict, void *key, unsigned int *idx)
{
    if (dict->tableSize > 0) {
        unsigned int i = (unsigned long)key % dict->tableSize;
        _TLinkedTable *list;
        if (idx != NULL) {
            *idx = i;
        }
        for (list = dict->lists[i]; list != NULL; list = list->next) {
            if (key == list->key) {
                break;
            }
        }
        return list;
    } else {
        return NULL;
    }
}


static _TLinkedTable *_lookup(_TCDictionary *dict, void *key)
{
    return __lookup(dict, key, NULL);
}


void _set(_TCDictionary *dict, void *key, void *value)
{
    unsigned int idx;

    if (dict->tableSize == 0 || dict->count >= dict->tableSize * 3 / 4) {
        _TLinkedTable **newLists;
        unsigned int newCapacity;
        unsigned int i;

        if (dict->tableSize == 0) {
            newCapacity = 13;
        } else {
            newCapacity = dict->tableSize * 2 + 1;
        }
        newLists = tAllocZero(sizeof(_TLinkedTable *) * newCapacity);

        for (i = 0; i < dict->tableSize; ++i) {
            _TLinkedTable *list;
            _TLinkedTable *next = NULL;
            for (list = dict->lists[i]; list != NULL; list = next) {
                unsigned int newIndex = (unsigned long)list->key % newCapacity;
                next = list->next;
                list->next = newLists[newIndex];
                newLists[newIndex] = list;
            }
        }
        dict->tableSize = newCapacity;
        tFree(dict->lists);
        dict->lists = newLists;
    }
    _TLinkedTable *list = __lookup(dict, key, &idx);
    if (list == NULL) {
        list = tAlloc(sizeof(_TLinkedTable));
        list->key = key;
        list->next = dict->lists[idx];
        dict->lists[idx] = list;
        ++(dict->count);
    }
    list->value = value;
}


static _TCDictionary *getDataDict()
{
    static _TCDictionary *dict = NULL;
    if (dict == NULL) {
        dict = tAllocZero(sizeof(_TCDictionary));
    }
    return dict;
}


static _TMockData *getData(void *key)
{
    _TLinkedTable *list = _lookup(getDataDict(), key);
    return list == NULL ? NULL : (_TMockData *)list->value;
}


static _TMockData *newData(void *key)
{
    _TMockData *data = tAllocZero(sizeof(_TMockData));
    data->messages = [[TMutableArray array] retain];
    data->totallyReplacedMethods = [[TMutableSet set] retain];
    _set(getDataDict(), key, data);
    return data;
}


static void removeData(void *key)
{
    _TMockData *data = getData(key);
    if (data != NULL) {
        [data->messages release];
        [data->totallyReplacedMethods release];
        _set(getDataDict(), key, NULL);
    }
}


static inline void checkForResponsibility(id obj, SEL sel)
{
    _TMockData *data = getData(obj);
    if (!class_respondsToSelector(data->originalClass, sel)) {
        @throw [TTestException exceptionWithFormat:
                @"<%s %s %p> cannot mock invalid message '%@'", class_getName(data->originalClass),
                data->rcvIsClass ? "class" : "instance", obj, [TUtils stringFromSelector: sel]];
    }
}


static byte __byteResult = 0;
static byte byteReturner(id self, SEL sel, ...)
{
    return __byteResult;
}


static id replay(id obj, SEL sel, ...)
{
    arglist_t argFrame = __builtin_apply_args();
    _TMockData *data = getData(obj);
    TMockMessage *msg = nil;
    id result = nil;
    TMutableArray *similars = [TMutableArray array];

    if (data == NULL) {
        @throw @"Received replay for receiver without data.";
    }
    for (id <TIterator> i = [data->messages reverseIterator];
            [i hasCurrent] && msg == nil; [i next]) {
        msg = [[i current] checkForSel: sel receiver: obj andArgs: argFrame
                addSimilarityTo: similars];
    }
    if (msg == nil) {
        if ([data->totallyReplacedMethods contains: [TUtils stringFromSelector: sel]]) {
            TMockMessage *unexpected = [TMockMessage unexpectedMockMessageWithSel: sel
                    receiver: obj andArgs: argFrame];
            if ([similars containsData]) {
                @throw [TTestException exceptionWithFormat: @"Unexpected message: %@\n"
                        @"Expected similar messages:\n  %@",
                        unexpected, [similars componentsJoinedByString: @"\n  "]];
            } else {
                @throw [TTestException exceptionWithFormat: @"Unexpected message: %@", unexpected];
            }
        } else {
            Method method = class_getInstanceMethod(data->originalClass, sel);
            __builtin_return(__builtin_apply((apply_t)method_getImplementation(method), argFrame,
                    encoding_getFrameSize(method_getTypeEncoding(method))));
        }
    } else {
        BOOL isByteReturn = NO;
        // FIXME support für alle typen -> beachten: __builtin_return erst _nach_ throw exception,
        // popResult aber _vorher_. -> Tests!
        // FIXME Apple Runtime hat keine typisierten Selektoren
        //       → aber man kann sich die Method von der Klasse holen, die auch Typen hat.
        char type = sel->sel_types != NULL ? encoding_getType(sel->sel_types) : _C_ID;
        switch (type) {
            case _C_CHR:
            case _C_UCHR:
                // FIXME test
                __byteResult = [msg popCharResult];
                isByteReturn = YES;
                break;
            case _C_SHT:
            case _C_USHT:
                // FIXME test
                result = (id)((size_t)[msg popShortResult]);
                break;
            case _C_INT:
            case _C_UINT:
                // FIXME test
                result = (id)((size_t)[msg popIntResult]);
                break;
            case _C_LNG:
            case _C_ULNG:
                // FIXME test
                result = (id)((size_t)[msg popLongResult]);
                break;
            case _C_LNG_LNG:
            case _C_ULNG_LNG:
                // FIXME test
                result = (id)((size_t)[msg popLongLongResult]);
                break;
            case _C_ID:
            case _C_CLASS:
            case _C_SEL:
            case _C_PTR:
            case _C_CHARPTR:
                // FIXME test
                result = [msg popPtrResult];
                break;
            case _C_VOID:
                [msg popVoidResult];
                break;
            default:
                @throw [TTestException exceptionWithFormat: @"Unsupported return type '%c' mocked.", type];
        }
        if ([msg exception] != nil) {
            @throw [msg exception];
        }
        // FIXME braucht man das wirklich? → Tests?
        // FIXME wenn ja, braucht man das auch für short, int (64bit), long long (32bit), float
        // (64bit) und double (32bit)
        if (isByteReturn) {
            __builtin_return(__builtin_apply((apply_t)byteReturner, argFrame, 0));
        }
    }
    return result;
}


#define _RETURN_FORWARD_0(type) return (type)0
#define _RETURN_FORWARD_1(type) return (type)self
#define _FORWARD_MESSAGE(type, returnself) static type type##Forward(id self, SEL cmd, SEL sel, arglist_t argFrame)\
{\
    _TMockData *data = getData(self);\
    data->isRecording = NO;\
    object_setClass(self, data->replayerClass);\
    checkForResponsibility(self, sel);\
    const char *typeEncoding =\
            method_getTypeEncoding(class_getInstanceMethod(data->originalClass, sel));\
    class_addMethod(data->replayerClass, sel, replay, typeEncoding);\
    TMockMessage *m = [TMockMessage mockMessageWithSel: sel receiver: self andArgs: argFrame];\
    if (data->file != NULL) {\
        [m setLocation: data->file : data->line];\
    }\
    [m setCallCount: data->callCount];\
    [data->messages addObject: m];\
    if (data->totallyReplaceMethod) {\
        [data->totallyReplacedMethods add: [TUtils stringFromSelector: sel]];\
    }\
    _RETURN_FORWARD_##returnself(type);\
}

#define FORWARD_MESSAGE(type) _FORWARD_MESSAGE(type, 1)
#define RETURNSELF_FORWARD_MESSAGE(type) _FORWARD_MESSAGE(type, 0)


// FIXME word-Typ-fowarder loswerden und Pointer ohne ifdef
// FIXME vllt. kann man ja doch alle ausser void self returnen lassen, wenn die forwarder immer id
// liefern (siehe types unten)


RETURNSELF_FORWARD_MESSAGE(byte)


RETURNSELF_FORWARD_MESSAGE(word)

#ifdef __LP64__

RETURNSELF_FORWARD_MESSAGE(dword)


FORWARD_MESSAGE(qword)

#else

FORWARD_MESSAGE(dword)


RETURNSELF_FORWARD_MESSAGE(qword)

#endif

RETURNSELF_FORWARD_MESSAGE(float)


RETURNSELF_FORWARD_MESSAGE(double)


FORWARD_MESSAGE(void)


RETURNSELF_FORWARD_MESSAGE(block)


static void addRecordMethods(Class class)
{
    // FIXME stimmen die größen? müsste das für 64bit nicht alles anders aussehen? → Berechner
    // (MAKRO) bauen!
    class_addMethod(class,
            sel_registerName("byteForward::"), (IMP)byteForward, "C16@0:4:8^(arglist=*[4c])12");
    class_addMethod(class,
            sel_registerName("wordForward::"), (IMP)wordForward, "S16@0:4:8^(arglist=*[4c])12");
    class_addMethod(class,
            sel_registerName("dwordForward::"), (IMP)dwordForward, "I16@0:4:8^(arglist=*[4c])12");
    class_addMethod(class,
            sel_registerName("qwordForward::"), (IMP)qwordForward, "Q16@0:4:8^(arglist=*[4c])12");
    class_addMethod(class,
            sel_registerName("floatForward::"), (IMP)floatForward, "f16@0:4:8^(arglist=*[4c])12");
    class_addMethod(class,
            sel_registerName("doubleForward::"), (IMP)doubleForward, "d16@0:4:8^(arglist=*[4c])12");
    class_addMethod(class,
            sel_registerName("voidForward::"), (IMP)voidForward, "v16@0:4:8^(arglist=*[4c])12");
    class_addMethod(class,
            sel_registerName("blockForward::"), (IMP)blockForward, "^v16@0:4:8^(arglist=*[4c])12");
}


static void verifyAndCleanupMocksFor(struct objc_object *self)
{
    _TMockData *data = getData(self);
    if (data != NULL) {
        object_setClass(self, data->originalClass);
        TMutableArray *pendingMessages = [[TMutableArray alloc] init];
        for (id <TIterator> i = [data->messages iterator]; [i hasCurrent]; [i next]) {
            TMockMessage *msg = [i current];
            if ([msg wantsCallCountChecking] && [msg hasPendingResults] &&
                    (![msg hasUnlimitedCallCount] || ![msg wasEverSent])) {
                [pendingMessages addObject: msg];
            }
        }
        // FIXME kann man die erzeugten Klassen irgendwie wieder loswerden?
        // FIXME die leaken hier derzeit
        removeData(self);
        @try {
            if ([pendingMessages containsData]) {
                @throw [TTestException exceptionWithFormat:
                        @"The following messages were not sent: %@", pendingMessages];
            }
        } @finally {
            [pendingMessages release];
        }
    }
}


static void dealloc_imp(id self, SEL sel)
{
    @try {
        verifyAndCleanupMocksFor(self);
    } @finally {
        [self dealloc];
    }
}


static Class class_imp(id self, SEL sel)
{
    return getData(self)->originalClass;
}


void verifyAndCleanupMocks()
{
    TMutableArray *exceptions = [TMutableArray array];
    _TCDictionary *dict = getDataDict();
    if (dict->tableSize > 0) {
        for (unsigned int i = 0; dict->tableSize > i; ++i) {
            _TLinkedTable *list = dict->lists[i];
            while (list != NULL) {
                @try {
                    verifyAndCleanupMocksFor(list->key);
                } @catch (id e) {
                    [exceptions addObject: e];
                }
                list = list->next;
            }
        }
    }
    if ([exceptions containsData]) {
        @throw [TTestException exceptionWithFormat:
                @"The following exceptions occured during mock verify: %@", exceptions];
    }
}


static Class recorderClass()
{
    static Class recorder = Nil;
    if (recorder == Nil) {
        Class root = objc_allocateClassPair(Nil, "TMockGhostRecorderRoot", 0);
        objc_registerClassPair(root);
        recorder = objc_allocateClassPair(root, "TMockGhostRecorder", 0);
        addRecordMethods(recorder);
        addRecordMethods(object_getClass(recorder));
        objc_registerClassPair(recorder);
    }
    return recorder;
}


static Class createReplayerClass(_TMockData *data)
{
    TString *name = [TString stringWithFormat: @"TGhostReplayer_%s_%p",
            class_getName(data->originalClass), data];
    Class class = objc_allocateClassPair(data->originalClass, [name cString], 0);
    class_addMethod(class, @selector(dealloc), (IMP)dealloc_imp, "v8@0:4");
    class_addMethod(class, @selector(class), (IMP)class_imp, "#8@0:4");
    objc_registerClassPair(class);
    return class;
}


static void mock(id obj, const char *file, int line)
{
    _TMockData *data = getData(obj);
    if (data == NULL) {
        data = newData(obj);
        if (class_isMetaClass(data->originalClass)) {
            data->rcvIsClass = YES;
        }
        data->originalClass = object_getClass(obj);
        Class replayer = createReplayerClass(data);
        data->replayerClass = data->rcvIsClass ? object_getClass(replayer) : replayer;
        object_setClass(obj, data->replayerClass);
    }
    if (data->isRecording) {
        @throw [TTestException exceptionWithMessage: @"'mock' was called while already recording."];
    }
    object_setClass(obj, data->rcvIsClass ? object_getClass(recorderClass()) : recorderClass());
    data->isRecording = YES;
    data->totallyReplaceMethod = NO;
    data->callCount = 1;
    data->file = file;
    data->line = line;
}


+ (Class)mock
{
    mock(self, NULL, 0);
    return self;
}


- mock
{
    mock(self, NULL, 0);
    return self;
}


static void stub(void *self)
{
    mock(self, NULL, 0);
    getData(self)->callCount = TUNIT_UNCHECKEDCALLCOUNT;
}


+ (Class)stub
{
    stub(self);
    return self;
}


- stub
{
    stub(self);
    return self;
}


static void _shouldReceive(void *self, const char *file, int line)
{
    mock(self, file, line);
    getData(self)->totallyReplaceMethod = YES;
}


+ (Class)shouldReceiveAt: (const char *)file : (int)line
{
    _shouldReceive(self, file, line);
    return self;
}


- shouldReceiveAt: (const char *)file : (int)line
{
    _shouldReceive(self, file, line);
    return self;
}


static void _shouldNotReceive(void *self, const char *file, int line)
{
    _shouldReceive(self, file, line);
    getData(self)->callCount = 0;
}


+ (Class)shouldNotReceiveAt: (const char *)file : (int)line
{
    _shouldNotReceive(self, file, line);
    return self;
}


- shouldNotReceiveAt: (const char *)file : (int)line
{
    _shouldNotReceive(self, file, line);
    return self;
}


+ (Class)andReturnInt: (int)result
{
    [[getData(self)->messages lastObject] pushIntResult: result];
    return self;
}


- andReturnInt: (int)result
{
    [[getData(self)->messages lastObject] pushIntResult: result];
    return self;
}


+ (Class)andReturn: (const void *)result
{
    [[getData(self)->messages lastObject] pushPtrResult: (void *)result];
    return self;
}


- andReturn: (const void *)result
{
    [[getData(self)->messages lastObject] pushPtrResult: (void *)result];
    return self;
}


+ (Class)returnBool: (BOOL)result
{
    [[getData(self)->messages lastObject] pushCharResult: result];
    return self;
}


- returnBool: (BOOL)result
{
    [[getData(self)->messages lastObject] pushCharResult: result];
    return self;
}


+ (Class)andReturnBool: (BOOL)result
{
    [[getData(self)->messages lastObject] pushCharResult: result];
    return self;
}


- andReturnBool: (BOOL)result
{
    [[getData(self)->messages lastObject] pushCharResult: result];
    return self;
}


static void setCallCount(void *self, unsigned int callCount)
{
    [[getData(self)->messages lastObject] setCallCount: callCount];
}


+ (Class)receiveTimes: (unsigned int)callCount
{
    setCallCount(self, callCount);
    return self;
}


- receiveTimes: (unsigned int)callCount
{
    setCallCount(self, callCount);
    return self;
}


static void setException(void *self, id exception)
{
    [[getData(self)->messages lastObject] setException: exception];
}


+ (Class)andThrow: exception
{
    setException(self, exception);
    return self;
}


- andThrow: exception
{
    setException(self, exception);
    return self;
}


static void skipParameterCheck(void *self, unsigned int idx)
{
    [[getData(self)->messages lastObject] skipParameterCheck: idx + 1];
}


+ (Class)skipParameterCheck: (unsigned int)idx
{
    skipParameterCheck(self, idx);
    return self;
}


- skipParameterCheck: (unsigned int)idx
{
    skipParameterCheck(self, idx);
    return self;
}


static void skipParameterChecks(void *self)
{
    [[getData(self)->messages lastObject] skipParameterChecks];
}


+ (Class)skipParameterChecks
{
    skipParameterChecks(self);
    return self;
}


- skipParameterChecks
{
    skipParameterChecks(self);
    return self;
}


static void ordered(void *self)
{
    [[getData(self)->messages lastObject] ordered];
}


+ (Class)ordered
{
    ordered(self);
    return self;
}


- ordered
{
    ordered(self);
    return self;
}


@end
