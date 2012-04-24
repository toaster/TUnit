//
// (C) Copyright Tilo Prütz
//

#include "TUnit/TObject.Mock.h"

#pragma .h #include <TFoundation/TFoundation.h>

#include <objc/runtime.h>
#include <string.h>

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


static void replay(ffi_cif *cif, void *result, void **args, FFIClosureUserData *userData)
{
    id obj = *(id*)args[0];
    _TMockData *data = getData(obj);

    if (data == NULL) {
        @throw @"Received replay for receiver without data.";
    }

    TInvocation *invocation = invocationFromFFIClosureCall(args, userData);
    TMockMessage *msg = nil;
    TMutableArray *similars = [TMutableArray array];
    for (id <TIterator> i = [data->messages reverseIterator];
            [i hasCurrent] && msg == nil; [i next]) {
        msg = [[i current] checkForInvocation: invocation addSimilarityTo: similars];
    }
    if (msg == nil) {
        SEL sel = [invocation selector];
        if ([data->totallyReplacedMethods contains: [TUtils stringFromSelector: sel]]) {
            TMockMessage *unexpected = [TMockMessage unexpectedMessageWithInvocation: invocation];
            if ([similars containsData]) {
                @throw [TTestException exceptionWithFormat: @"Unexpected message: %@\n"
                        @"Expected similar messages:\n  %@",
                        unexpected, [similars componentsJoinedByString: @"\n  "]];
            } else {
                @throw [TTestException exceptionWithFormat: @"Unexpected message: %@", unexpected];
            }
        } else {
            ffi_call(cif, (void *)class_getMethodImplementation(data->originalClass, sel),
                    result, args);
        }
    } else {
        [invocation setReturnValue: [msg popResult]];
        [invocation getReturnValue: result];
        if ([msg exception] != nil) {
            @throw [msg exception];
        }
    }
}


static void forward(id self, SEL cmd, TInvocation *invocation)
{
    _TMockData *data = getData(self);
    data->isRecording = NO;
    object_setClass(self, data->replayerClass);

    SEL sel = [invocation selector];
    checkForResponsibility(self, sel);

    // FIXME Mehrfachrecordings erzeugen immer wieder dieselbe closure
    // FIXME Memory-Leak: Wer räumt die erzeugte closure weg?
    const char *types = method_getTypeEncoding(class_getInstanceMethod(data->originalClass, sel));
    TMethodSignature *sig = [TMethodSignature signatureWithObjCTypes: types];
    class_addMethod(data->replayerClass, sel, ffiClosure(sig, replay), types);

    TMockMessage *m = [TMockMessage messageWithInvocation: invocation];
    if (data->file != NULL) {
        [m setLocation: data->file : data->line];
    }
    [m setCallCount: data->callCount];
    [data->messages addObject: m];
    if (data->totallyReplaceMethod) {
        [data->totallyReplacedMethods add: [TUtils stringFromSelector: sel]];
    }

    unsigned int resultLength = [[invocation methodSignature] methodReturnLength];
    char result[resultLength];
    memcpy(result, &self, resultLength > sizeof(id) ? sizeof(id) : resultLength);
    [invocation setReturnValue: result];
}


static void addRecordMethods(Class class)
{
    Method m = class_getInstanceMethod([TObject class], @selector(methodSignatureForSelector:));
    class_addMethod(class, sel_registerName("methodSignatureForSelector:"),
            method_getImplementation(m), method_getTypeEncoding(m));
    class_addMethod(class, sel_registerName("forward:"), (IMP)forward,
            method_getTypeEncoding(class_getInstanceMethod([TObject class], @selector(forward:))));
}


static void verifyAndCleanupMocksFor(id self)
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
    return getData(self)->rcvIsClass ? self : getData(self)->originalClass;
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
        data->originalClass = object_getClass(obj);
        if (class_isMetaClass(data->originalClass)) {
            data->rcvIsClass = YES;
        }
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
