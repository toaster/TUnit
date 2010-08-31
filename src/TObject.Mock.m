//
// (C) Copyright Tilo Prütz
//

#include "TUnit/TObject.Mock.h"

#pragma .h #include <TFoundation/TFoundation.h>

#include <objc/objc-api.h>
#include <objc/encoding.h>
#include <objc/sarray.h>

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
    Class superClass;
    MethodList *methods;
    BOOL isRecording;
    TMutableArray *messages;
    BOOL totallyReplaceMethod;
    int callCount;
    TMutableSet *totallyReplacedMethods;
    const char *file;
    int line;
} _TMockData;


static _TLinkedTable *__lookup(_TCDictionary *dict, void *key, unsigned int *index)
{
    if (dict->tableSize > 0) {
        unsigned int i = (unsigned int)key % dict->tableSize;
        _TLinkedTable *list;
        if (index != NULL) {
            *index = i;
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
    unsigned int index;
    _TLinkedTable *list;

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
                unsigned int newIndex = (unsigned int)list->key % newCapacity;
                next = list->next;
                list->next = newLists[newIndex];
                newLists[newIndex] = list;
            }
        }
        dict->tableSize = newCapacity;
        tFree(dict->lists);
        dict->lists = newLists;
    }
    list = __lookup(dict, key, &index);
    if (list == NULL) {
        list = tAlloc(sizeof(_TLinkedTable));
        list->key = key;
        list->next = dict->lists[index];
        dict->lists[index] = list;
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


static inline void checkForResponsibility(id self, SEL sel)
{
    _TMockData *data = getData(self);
    if (class_get_instance_method(data->superClass, sel) == METHOD_NULL) {
        @throw [TTestException exceptionWithFormat: @"<%@ %s %p> cannot mock invalid message '%@'",
                [data->superClass className], object_is_instance(self) ? "instance" : "class", self,
                [TUtils stringFromSelector: sel]];
    }
}


static byte __byteResult = 0;
static byte byteReturner(id self, SEL sel, ...)
{
    return __byteResult;
}


static id replay(id self, SEL sel, ...)
{
    arglist_t argFrame = __builtin_apply_args();
    _TMockData *data = getData(self);
    TMockMessage *msg = nil;
    id result = nil;
    TMutableArray *similars = [TMutableArray array];

    if (data != NULL) {
        for (id <TIterator> i = [data->messages reverseIterator];
                [i hasCurrent] && msg == nil; [i next]) {
            msg = [[i current] checkForSel: sel receiver: self andArgs: argFrame
                    addSimilarityTo: similars];
        }
    }
    if (msg == nil) {
        if ([data->totallyReplacedMethods contains: [TUtils stringFromSelector: sel]]) {
            TMockMessage *unexpected = [TMockMessage unexpectedMockMessageWithSel: sel
                    receiver: self andArgs: argFrame];
            if ([similars containsData]) {
                @throw [TTestException exceptionWithFormat: @"Unexpected message: %@\n"
                        @"Expected similar messages:\n  %@",
                        unexpected, [similars componentsJoinedByString: @"\n  "]];
            } else {
                @throw [TTestException exceptionWithFormat: @"Unexpected message: %@", unexpected];
            }
        } else {
            Method *method = class_get_instance_method(self->class_pointer->super_class, sel);
            __builtin_return(__builtin_apply((apply_t)method->method_imp, argFrame,
                    atoi(objc_skip_typespec(method->method_types))));
        }
    } else {
        BOOL isByteReturn = NO;
        // FIXME support für alle typen -> beachten: __builtin_return erst _nach_ throw exception,
        // popResult aber _vorher_. -> Tests!
        char type = sel->sel_types != NULL ? sel->sel_types[0] : _C_ID;
        switch (type) {
            case _C_CHR:
            case _C_UCHR:
                __byteResult = [msg popByteResult];
                isByteReturn = YES;
                break;
            case _C_ID:
            case _C_CLASS:
            case _C_SEL:
            case _C_PTR:
            case _C_CHARPTR:
            case _C_ATOM:
            case _C_INT:
            case _C_UINT:
            case _C_LNG:
            case _C_ULNG:
                result = (id)[msg popDwordResult];
                break;
            case _C_VOID:
                [msg popVoidResult];
                break;
            default:
                @throw [TTestException
                        exceptionWithFormat: @"Unsupported return type '%c' mocked.", type];
        }
        if ([msg exception] != nil) {
            @throw [msg exception];
        }
        if (isByteReturn) {
            __builtin_return(__builtin_apply((apply_t)byteReturner, argFrame, 0));
        }
    }
    return result;
}


void registerMethod(Class class, SEL sel, IMP function)
{
    BOOL methodAlreadyRegistered = NO;
    if (class->methods == NULL) {
        class->methods = tAllocZero(sizeof(MethodList));
    } else {
        for (unsigned int i = 0; !methodAlreadyRegistered &&
                class->methods->method_count > i; ++i) {
            if (sel_eq(class->methods->method_list[i].method_name, sel)) {
                methodAlreadyRegistered = YES;
            }
        }
        if (!methodAlreadyRegistered) {
            class->methods = tRealloc(class->methods,
                    sizeof(MethodList) + class->methods->method_count * sizeof(Method));
        }
    }
    if (!methodAlreadyRegistered) {
        Method *method = &class->methods->method_list[class->methods->method_count++];
        method->method_name = sel;
        method->method_types = sel->sel_types;
        method->method_imp = function;
    }
    __objc_update_dispatch_table_for_class(class);
}


#define _RETURN_FORWARD_0(type) return (type)0
#define _RETURN_FORWARD_1(type) return (type)self
#define _FORWARD_MESSAGE(type, returnself) static type type##Forward(id self, SEL cmd, SEL sel, arglist_t argFrame)\
{\
    _TMockData *data = getData(self);\
    data->isRecording = NO;\
    Class class = self->class_pointer;\
    class->super_class = data->superClass;\
    class->methods = data->methods;\
    checkForResponsibility(self, sel);\
    registerMethod(class, sel, replay);\
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


RETURNSELF_FORWARD_MESSAGE(byte)


RETURNSELF_FORWARD_MESSAGE(word)


FORWARD_MESSAGE(dword)


RETURNSELF_FORWARD_MESSAGE(qword)


RETURNSELF_FORWARD_MESSAGE(float)


RETURNSELF_FORWARD_MESSAGE(double)


FORWARD_MESSAGE(void)


RETURNSELF_FORWARD_MESSAGE(block)


static MethodList *recordMethods()
{
    static MethodList *methods = NULL;
    if (methods == NULL) {
        methods = tAlloc(sizeof(MethodList) + 8 * sizeof(Method));
        methods->method_next = NULL;
        methods->method_count = 8;

        Method *method = &methods->method_list[0];
        method->method_types = "C16@0:4:8^(arglist=*[4c])12";
        method->method_name = sel_register_typed_name("byteForward::", method->method_types);
        method->method_imp = (IMP)byteForward;

        method = &methods->method_list[1];
        method->method_types = "S16@0:4:8^(arglist=*[4c])12";
        method->method_name = sel_register_typed_name("wordForward::", method->method_types);
        method->method_imp = (IMP)wordForward;

        method = &methods->method_list[2];
        method->method_types = "I16@0:4:8^(arglist=*[4c])12";
        method->method_name = sel_register_typed_name("dwordForward::", method->method_types);
        method->method_imp = (IMP)dwordForward;

        method = &methods->method_list[3];
        method->method_types = "Q16@0:4:8^(arglist=*[4c])12";
        method->method_name = sel_register_typed_name("qwordForward::", method->method_types);
        method->method_imp = (IMP)qwordForward;

        method = &methods->method_list[4];
        method->method_types = "f16@0:4:8^(arglist=*[4c])12";
        method->method_name = sel_register_typed_name("floatForward::", method->method_types);
        method->method_imp = (IMP)floatForward;

        method = &methods->method_list[5];
        method->method_types = "d16@0:4:8^(arglist=*[4c])12";
        method->method_name = sel_register_typed_name("doubleForward::", method->method_types);
        method->method_imp = (IMP)doubleForward;

        method = &methods->method_list[6];
        method->method_types = "v16@0:4:8^(arglist=*[4c])12";
        method->method_name = sel_register_typed_name("voidForward::", method->method_types);
        method->method_imp = (IMP)voidForward;

        method = &methods->method_list[7];
        method->method_types = "^v16@0:4:8^(arglist=*[4c])12";
        method->method_name = sel_register_typed_name("blockForward::", method->method_types);
        method->method_imp = (IMP)blockForward;
    }
    return methods;
}


static void verifyAndCleanupMocksFor(struct objc_object *self)
{
    _TMockData *data = getData(self);
    if (data != NULL) {
        Class ghost = self->class_pointer;
        self->class_pointer = self->class_pointer->super_class;
        if (ghost->methods != recordMethods()) {
            MethodList *methods = ghost->methods;
            if (ghost->dtable != objc_get_uninstalled_dtable() && ghost->dtable != NULL) {
                sarray_free(ghost->dtable);
            }
            while (methods != NULL) {
                MethodList *tmp = methods->method_next;
                tFree(methods);
                methods = tmp;
            }
            tFree(ghost);
        }
        TMutableArray *pendingMessages = [[TMutableArray alloc] init];
        for (id <TIterator> i = [data->messages iterator]; [i hasCurrent]; [i next]) {
            TMockMessage *msg = [i current];
            if ([msg wantsCallCountChecking] && [msg hasPendingResults] &&
                    (![msg hasUnlimitedCallCount] || ![msg wasEverSent])) {
                [pendingMessages addObject: msg];
            }
        }
        removeData(self);
        @try {
            if ([pendingMessages containsData]) {
                @throw [TTestException exceptionWithFormat:
                        @"The following messages were not sent: %@",
                        pendingMessages];
            }
        } @finally {
            [pendingMessages release];
        }
    }
}


static void dealloc(id self, SEL sel)
{
    @try {
        verifyAndCleanupMocksFor(self);
    } @finally {
        [self dealloc];
    }
}


static Class class(id self, SEL sel)
{
    return self->class_pointer->super_class;
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


static void mock(struct objc_object *self, const char *file, int line)
{
    _TMockData *data = getData(self);
    if (data == NULL) {
        Class old = self->class_pointer;
        size_t classSize = sizeof(struct objc_class);
        Class new = tAlloc(classSize);
        memcpy(new, old, classSize);
        new->super_class = old;
        new->subclass_list = NULL;
        new->sibling_class = NULL;
        new->methods = NULL;
        new->dtable = NULL;
        __objc_install_premature_dtable(new);
        if (object_is_instance(self)) {
            registerMethod(new, @selector(dealloc), (IMP)dealloc);
            registerMethod(new, @selector(class), (IMP)class);
        }
        self->class_pointer = new;
        data = newData(self);
    }
    if (data->isRecording) {
        @throw [TTestException exceptionWithMessage: @"'mock' was called while already recording."];
    }
    Class class = self->class_pointer;
    data->superClass = class->super_class;
    class->super_class = Nil;
    data->methods = class->methods;
    class->methods = recordMethods();
    data->isRecording = YES;
    data->totallyReplaceMethod = NO;
    data->callCount = 1;
    data->file = file;
    data->line = line;
    __objc_update_dispatch_table_for_class(class);
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


static void setDwordResult(void *self, dword result)
{
    [[getData(self)->messages lastObject] pushDwordResult: result];
}


+ (Class)andReturnInt: (int)result
{
    setDwordResult(self, result);
    return self;
}


- andReturnInt: (int)result
{
    setDwordResult(self, result);
    return self;
}


+ (Class)andReturn: (const void *)result
{
    setDwordResult(self, (dword)result);
    return self;
}


- andReturn: (const void *)result
{
    setDwordResult(self, (dword)result);
    return self;
}


static void setByteResult(void *self, byte result)
{
    [[getData(self)->messages lastObject] pushByteResult: result];
}


+ (Class)returnBool: (BOOL)result
{
    setByteResult(self, (byte)result);
    return self;
}


- returnBool: (BOOL)result
{
    setByteResult(self, (byte)result);
    return self;
}


+ (Class)andReturnBool: (BOOL)result
{
    setByteResult(self, (byte)result);
    return self;
}


- andReturnBool: (BOOL)result
{
    setByteResult(self, (byte)result);
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


static void skipParameterCheck(void *self, unsigned int index)
{
    [[getData(self)->messages lastObject] skipParameterCheck: index + 1];
}


+ (Class)skipParameterCheck: (unsigned int)index
{
    skipParameterCheck(self, index);
    return self;
}


- skipParameterCheck: (unsigned int)index
{
    skipParameterCheck(self, index);
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
