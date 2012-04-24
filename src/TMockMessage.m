//
// (C) Copyright Tilo Prütz
//

#include "TUnit/TMockMessage.h"

#pragma .h #include <TFoundation/TFoundation.h>

#pragma .h #include "TUnit/TMock.h"

#include <math.h>
#include <objc/runtime.h>
#include <string.h>
#include <ctype.h>

#include "TUnit/TTestException.h"

#pragma .h #define TUNIT_UNLIMITEDCALLCOUNT 0xFFFFFFFE
#pragma .h #define TUNIT_UNCHECKEDCALLCOUNT 0xFFFFFFFF

#pragma .h typedef struct _TMockResult TMockResult;
#pragma .h typedef union _TMockVariable TMockVariable;

union _TMockVariable {
    long long value;
    // TODO union/struct/array
    TString *aCharArray;
};

struct _TMockResult {
    char value[8];
    unsigned int count;
    unsigned int used;
    TMockResult *next;
};


@implementation TMockMessage:TObject
{
    SEL _sel;
    TMockResult *_results;
    TMockResult *_lastResult;
    TMockResult *_nextResult;
    BOOL _overrideResult;
    // Only for equality tests! NOT retained! Do NOT send messages to it!
    id _receiver;
    int _argCount;
    TMockVariable *_args;
    BOOL *_skipCheck;
    TMutableArray *_argStrings;
    BOOL _unexpected;
    id _exception;
    BOOL _isOrdered;
    const char *_file;
    int _line;
    unsigned int _resultSize;
}


static inline TString *_charString(char c)
{
    return [TString stringWithFormat: @"(char)0x%02x", c & 0xFF];
}


static inline TString *_shortString(short s, BOOL isSigned)
{
    return [TString stringWithFormat: (isSigned ? @"(short)%d" : @"(short)%u"), s];
}


static inline TString *_intString(int i, BOOL isSigned)
{
    return [TString stringWithFormat: (isSigned ? @"(int)%i" : @"(int)%u"), i];
}


static inline TString *_longString(long l, BOOL isSigned)
{
    return [TString stringWithFormat: (isSigned ? @"(long)%ld" : @"(long)%lu"), l];
}


static inline TString *_longLongString(long long ll, BOOL isSigned)
{
    return [TString stringWithFormat: (isSigned ? @"(long long)%lld" : @"(long long)%llu"), ll];
}


static inline TString *_ptrString(void *p)
{
    return [TString stringWithFormat: @"%p", p];
}


static inline TString *_floatString(float f)
{
    return [TString stringWithFormat: @"(float)%f", f];
}


static inline TString *_doubleString(double d)
{
    return [TString stringWithFormat: @"(double)%lf", d];
}


static inline BOOL _isTMock(id object)
{
    return [TMock class] == object_getClass(object);
}


#define OBJ_IS_INSTANCE(obj) !class_isMetaClass(object_getClass(obj))


static inline TString *_idString(id object)
{
    if (_isTMock(object)) {
        return [TString stringWithFormat: @"<%@>", [TMockController descriptionFor: (TMock *)object]];
// FIXME: kommt von ip - testen & Test bauen, ob das irgendwie sinnvoll ist, oder ob die
// Default-Ausgabe schöner ist.
//    } else if ([Protocol class] == class) {
//        return [TString stringWithFormat: @"@protocol(%@)", [(Protocol *)object name]];
    } else {
        return [TString stringWithFormat: @"<%@ %s %@>", [object className],
                OBJ_IS_INSTANCE(object) ? "instance" : "class", object];
    }
}


static inline TString *_charArrayString(char *array, unsigned size)
{
    TStringOutputStream *s = [TStringOutputStream stream];
    [s writeFormat: @"(char[%u])", size];
    for (unsigned i = 0; i < size; ++i) {
        [s writeFormat: @" 0x%02x", array[i]];
    }
    return [s targetString];
}


static inline TString *_selString(SEL sel)
{
    return [TString stringWithFormat: @"@selector(%@)", [TUtils stringFromSelector: sel]];
}


static inline TString *_classString(Class class)
{
    return [TString stringWithFormat: @"@class(%@)", [TUtils stringFromClass: class]];
}


struct objc_method {
    SEL method_name;
    const char *method_types;
    IMP method_imp;
};


static inline BOOL _parameterValues(TInvocation *invocation,
        TMockVariable **values, TMutableArray *argStrings,
        BOOL validate, unsigned int expectedArgCount, TMockVariable *args, BOOL *skipCheck)
{
    SEL sel = [invocation selector];
    id receiver = [invocation target];
    TMethodSignature *sig = [invocation methodSignature];
    unsigned int argCount = [sig numberOfArguments];

    if (validate && expectedArgCount != argCount) {
        @throw [TTestException exceptionWithFormat: @"Invalid argument count %d (should be %d) "
                @"for message '%@' to %@.", argCount, expectedArgCount,
                [TUtils stringFromSelector: sel], _idString(receiver)];
    }

    BOOL messageIsValid = YES;
    if (values != NULL) {
        *values = (TMockVariable *)tAllocZero(argCount * sizeof(TMockVariable));
    }
    char arg[[sig frameLength]];
    for (int i = 0; i < argCount; ++i) {
        [invocation getArgument: arg atIndex: i];
        char type = encoding_getType([sig getArgumentTypeAtIndex: i]);
        BOOL isValid = YES;
        switch (type) {
            case _C_CHR:
            case _C_UCHR:
                [argStrings addObject: _charString(*arg)];
                if (!validate) {
                    (*values)[i].value = *arg;
                } else if (isValid) {
                    isValid = (*arg == args[i].value);
                }
                break;
            case _C_SHT:
            case _C_USHT:
                [argStrings addObject: _shortString(*((short *)arg), type == _C_SHT)];
                if (!validate) {
                    (*values)[i].value = *((short *)arg);
                } else if (isValid) {
                    isValid = (*((short *)arg) == args[i].value);
                }
                break;
            case _C_ID:
                if (i > 0) {
                    [argStrings addObject: _idString(*((id *)arg))];
                }
                if (!validate) {
                    (*values)[i].value = (size_t)*((id *)arg);
                } else if (isValid && i > 0) {
                    // arg 0 is the receiver -> maybe a mock that must not get a message here.
                    // It's validity has already been approved.
                    id value = *((id *)arg);
                    id expectedValue = (id)((size_t)args[i].value);

                    isValid = (value == expectedValue) || [value isEqual: expectedValue];
// FIXME: das kommt von ip - Nutzen verstehen, testen und ggf. einbauen
//// #define DEBUG_COMPARE
//#ifdef DEBUG_COMPARE
//                        fprintf(stderr, "value class compare: %s\n", object_get_class(value) == [Protocol class] ? "Yes" : "No");
//#endif
//                        if (object_get_class(value) == [Protocol class]) {
//#ifdef DEBUG_COMPARE
//                            BOOL isIdentical = value == expectedValue;
//                            fprintf(stderr, "identical: %s\n", isIdentical ?
//                                     "Yes" : "No");
//                            isValid = isIdentical;
//                            if (!isIdentical) {
//                                BOOL isSomething =
//                                        object_get_class(expectedValue) ==
//                                        [Protocol class] && 0 == strcmp(
//                                        [(Protocol *)value name],
//                                        [(Protocol *)expectedValue name]);
//                                fprintf(stderr, "exp v. class compare: %s\n",
//                                        isSomething ? "Yes" : "No");
//                                isValid = isSomething;
//                                if (!isSomething) {
//                                    BOOL isEqual = [value isEqual: expectedValue];
//                                    fprintf(stderr, "equal: %s\n", isEqual ?
//                                        "Yes" : "No");
//                                    isValid = isEqual;
//                                }
//                            }
//#else
//                            isValid = (value == expectedValue) ||
//                                    (object_get_class(expectedValue) ==
//                                     [Protocol class] &&
//                                     strcmp([(Protocol *)value name],
//                                     [(Protocol *)expectedValue name]) == 0) ||
//                                    [value isEqual: expectedValue];
//#endif
//                        } else {
//#ifdef DEBUG_COMPARE
//                            BOOL isIdentical = value == expectedValue;
//                            fprintf(stderr, "(2) identical: %s\n", isIdentical ?
//                                    "Yes" : "No");
//                            isValid = isIdentical;
//                            if (!isIdentical) {
//                                BOOL isEqual = [value isEqual: expectedValue];
//                                fprintf(stderr, "(2) equal    : %s\n", isEqual ?
//                                        "Yes" : "No");
//                                isValid = isEqual;
//                                if (!isEqual) {
//                                    fprintf(stderr, "value = %s\n",
//                                            STRING([value description]));
//                                    fprintf(stderr, "expected value = %s\n",
//                                    STRING([expectedValue description]));
//                                }
//                            }
//#else
//                            isValid = (value == expectedValue) ||
//                                    [value isEqual: expectedValue];
//#endif
//                        }
                }
                break;
            case _C_SEL:
                if (i > 1) {
                    [argStrings addObject: _selString(*((SEL *)arg))];
                    if (!validate) {
                        (*values)[i].value = (size_t)*((SEL *)arg);
                    } else if (isValid) {
                        isValid = sel_eq(*((SEL *)arg), (SEL)((size_t)args[i].value));
                    }
                }
                break;
            case _C_CLASS:
                [argStrings addObject: _classString(*((Class *)arg))];
                if (!validate) {
                    (*values)[i].value = (size_t)*((Class *)arg);
                } else if (isValid && i > 1) {
                    isValid = ((size_t)*((Class *)arg) == args[i].value);
                }
                break;
            case _C_PTR:
            case _C_CHARPTR:
                [argStrings addObject: _ptrString(*((void **)arg))];
                if (!validate) {
                    (*values)[i].value = (size_t)*((void **)arg);
                } else if (isValid && i > 1) {
                    isValid = ((size_t)*((void **)arg) == args[i].value);
                }
                break;
            case _C_INT:
            case _C_UINT:
                [argStrings addObject: _intString(*((int *)arg), type == _C_INT)];
                if (!validate) {
                    (*values)[i].value = *((int *)arg);
                } else if (isValid && i > 1) {
                    isValid = (*((int *)arg) == args[i].value);
                }
                break;
            case _C_LNG:
            case _C_ULNG:
                [argStrings addObject: _longString(*((long *)arg), type)];
                if (!validate) {
                    (*values)[i].value = *((long *)arg);
                } else if (isValid && i > 1) {
                    isValid = (*((long *)arg) == args[i].value);
                }
                break;
            case _C_LNG_LNG:
            case _C_ULNG_LNG:
                [argStrings addObject: _longLongString(*((long long *)arg), type == _C_LNG_LNG)];
                if (!validate) {
                    (*values)[i].value = *((long long *)arg);
                } else if (isValid) {
                    isValid = (*((long long *)arg) == args[i].value);
                }
                break;
            case _C_FLT:
                [argStrings addObject: _floatString(*((float *)arg))];
                if (!validate) {
                    (*values)[i].value = *((long long *)&*((float *)arg));
                } else if (isValid) {
                    isValid = (*((float *)arg) == *((float *)&args[i].value));
                }
                break;
            case _C_DBL:
                [argStrings addObject: _doubleString(*((double *)arg))];
                if (!validate) {
                    (*values)[i].value = *((long long *)&*((double *)arg));
                } else if (isValid) {
                    isValid = (*((double *)arg) == *((double *)&args[i].value));
                }
                break;
            // FIXME beginnen Arrays wirklich mit _C_ARY_B oder doch mit _C_PTR → evaluieren
            // FIXME auf jeden Fall können sie mit _C_CONST beginnen :)
            case _C_ARY_B:
                /*{
                    // FIXME das passt noch nicht
                    char *end = strchr(cur, _C_ARY_E);
                    char elementType = *(end - 1);
                    if (elementType == _C_CHR || elementType == _C_UCHR) {
                        unsigned arraySize = 0;
                        for (int j = 0; j < end - cur - 2; ++j) {
                            arraySize += (*(end - 2 - j) - '0') * pow(10, j);
                        }
                        [argStrings addObject: _charArrayString(*(char **)arg, arraySize)];
                        TString *value = [TString stringWithCString: *(char **)arg length: arraySize];
                        if (!validate) {
                            (*values)[i].aCharArray = value;
                        } else {
                            isValid = [args[i].aCharArray isEqual: value];
                        }
                        break;
                    } else {
                        // Other array types are not supported yet.
                    }
                }*/
            // Other block parameters are not supported yet.
            case _C_UNION_B:
            case _C_STRUCT_B:
            // Parameters must not be void.
            case _C_VOID:
            case _C_ONEWAY:
            // Bitfield, Undefined, Vector and (Array, Union, Struct) End
            // are not supported.
            case _C_BFLD:
            case _C_UNDEF:
            case _C_VECTOR:
            case _C_ARY_E:
            case _C_UNION_E:
            case _C_STRUCT_E:
            default:
                @throw [TTestException exceptionWithFormat:
                        @"Invalid parameter type '%c' for forwarded message '%@' parameter %d.",
                        type, [TUtils stringFromSelector: sel], i];
        }
        if (validate && !isValid && !skipCheck[i]) {
            messageIsValid = NO;
        }
    }
    return !validate || messageIsValid;
}


+ messageWithInvocation: (TInvocation *)invocation
{
    return [[[self alloc] initWithInvocation: invocation] autorelease];
}


+ unexpectedMessageWithInvocation: (TInvocation *)invocation
{
    TMockMessage *msg = [self messageWithInvocation: invocation];
    msg->_unexpected = YES;
    return msg;
}


- (void)__newResult
{
    if (_overrideResult) {
        _overrideResult = NO;
    } else {
        TMockResult *result = (TMockResult *)tAllocZero(sizeof(TMockResult));
        if (_results == NULL) {
            _results = result;
            _nextResult = result;
        }
        if (_lastResult != NULL) {
            _lastResult->next = result;
        }
        _lastResult = result;
        _lastResult->count = 1;
        if (_nextResult == NULL) {
            _nextResult = _lastResult;
        }
    }
}


- initWithInvocation: (TInvocation *)invocation
{
    [self init];
    _sel = [invocation selector];
    _receiver = [invocation target];
    _argStrings = [[TMutableArray array] retain];
    _argCount = [[invocation methodSignature] numberOfArguments];
    _parameterValues(invocation, &_args, _argStrings, NO, 0, NULL, NULL);
    if (_argCount > 0) {
        _skipCheck = (BOOL *)tAllocZero(_argCount * sizeof(BOOL));
    }
    [self __newResult];
    _overrideResult = YES;
    _resultSize = [[invocation methodSignature] methodReturnLength];
    return self;
}


- (void)dealloc
{
    TMockResult *tmp = _results;

    while (tmp != NULL) {
        _results = tmp->next;
        tFree(tmp);
        tmp = _results;
    }
    tFree(_args);
    tFree(_skipCheck);
    [_argStrings release];
    [_exception release];
    [super dealloc];
}


static TMutableArray *__orderedMessages = nil;
+ (void)addOrderedMessage: (TMockMessage *)msg
{
    [__orderedMessages addObject: msg];
}


+ (BOOL)consumeIfOrdered: (TMockMessage *)msg
{
    if (msg->_isOrdered) {
        if ([__orderedMessages firstObject] != msg) {
            return NO;
        }
        if (![msg hasAtLeastTwoPendingResults]) {
            [__orderedMessages removeFirstObject];
        }
    }
    return YES;
}


+ (void)cleanupOrderedMessages
{
    [__orderedMessages release];
    __orderedMessages = [[TMutableArray array] retain];
}


- (TMockResult *)__popResult
{
    TMockResult *result = _nextResult;

    if (_nextResult != NULL) {
        if (++(_nextResult->used) == _nextResult->count &&
                _nextResult->count != TUNIT_UNLIMITEDCALLCOUNT &&
                _nextResult->count != TUNIT_UNCHECKEDCALLCOUNT) {
            _nextResult = _nextResult->next;
        }
    }
    return result;
}


#pragma .h #define RESULT_ACCESSOR_H(type, Type) - (void)push##Type##Result: (type)result;

#define RESULT_ACCESSOR(type, Type) - (void)push##Type##Result: (type)result\
{\
    [self __newResult];\
    memcpy(_lastResult->value, &result, _resultSize);\
};


- (void *)popResult
{
    TMockResult *r = [self __popResult];
    if (r != NULL) {
        return r->value;
    }
    return NULL;
}


#pragma .h RESULT_ACCESSOR_H(char, Char);
RESULT_ACCESSOR(char, Char);


#pragma .h RESULT_ACCESSOR_H(short, Short);
RESULT_ACCESSOR(short, Short);


#pragma .h RESULT_ACCESSOR_H(int, Int);
RESULT_ACCESSOR(int, Int);


#pragma .h RESULT_ACCESSOR_H(long, Long);
RESULT_ACCESSOR(long, Long);


#pragma .h RESULT_ACCESSOR_H(long long, LongLong);
RESULT_ACCESSOR(long long, LongLong);


#pragma .h RESULT_ACCESSOR_H(void *, Ptr);
RESULT_ACCESSOR(void *, Ptr);


#pragma .h RESULT_ACCESSOR_H(float, Float);
RESULT_ACCESSOR(float, Float);


#pragma .h RESULT_ACCESSOR_H(double, Double);
RESULT_ACCESSOR(double, Double);


#pragma .h #undef RESULT_ACCESSOR_H


- (void)setException: e
{
    [e retain];
    [_exception release];
    _exception = e;
}


- exception
{
    return _exception;
}


- skipParameterChecks
{
    for (int i = 0; i < _argCount; ++i) {
        _skipCheck[i] = YES;
    }
    return nil;
}


- skipParameterCheck: (unsigned int)idx
{
    if (idx < _argCount) {
        _skipCheck[idx] = YES;
    } else {
        @throw [TTestException exceptionWithFormat: @"Index %u is too high for the recent "
                @"message which had only %u arguments.", idx, _argCount];
    }
    return nil;
}


- (void)setCallCount: (unsigned int)callCount
{
    _lastResult->count = callCount;
}


- (BOOL)hasAtLeastPendingResults: (int)min
{
    return _nextResult != NULL && (_nextResult->count >= _nextResult->used + min ||
            [self hasUnlimitedCallCount]);
}


- (BOOL)hasPendingResults
{
    return [self hasAtLeastPendingResults: 1];
}


- (BOOL)hasAtLeastTwoPendingResults
{
    return [self hasAtLeastPendingResults: 2];
}


- (BOOL)wantsNotToBeCalled
{
    return _lastResult != NULL && _lastResult->count == 0;
}


- (BOOL)hasUnlimitedCallCount
{
    return _nextResult != NULL &&
            (_nextResult->count == TUNIT_UNLIMITEDCALLCOUNT || _nextResult->count == TUNIT_UNCHECKEDCALLCOUNT);
}


- (BOOL)wantsCallCountChecking
{
    return _nextResult != NULL && _nextResult->count != TUNIT_UNCHECKEDCALLCOUNT;
}


- (BOOL)wasEverSent
{
    return _results != NULL && _results->used > 0;
}


- (BOOL)isForSel: (SEL)sel andReceiver: receiver
{
    return sel_eq(_sel, sel) && _receiver == receiver;
}


- (BOOL)isForInvocation: (TInvocation *)invocation
{
    return (BOOL)_parameterValues(invocation, NULL, nil, YES, _argCount, _args, _skipCheck);
}


- (void)describeOnStream: (TOutputStream *)stream
{
    [stream writeObject: @"["];
    [stream writeObject: _idString(_receiver)];
    TString *selString = [TUtils stringFromSelector: _sel];
    TArray *selArray = [selString componentsSeparatedByString: @":"];

    id <TIterator> args = [_argStrings iterator];
    int idx = 2;
    for (id <TIterator> i = [[selArray arrayByRemovingLastObject] iterator];
            [i hasCurrent]; [i next]) {
        if ([args hasCurrent] || [[i current] length] > 0) {
            [stream writeByte: ' '];
        }
        [stream writeObject: [i current]];
        if ([args hasCurrent]) {
            [stream writeObject: @": "];
            if (_skipCheck[idx]) {
                [stream writeObject: @"UNCHECKED"];
            } else {
                [stream writeObject: [args current]];
            }
            [args next];
        }
        ++idx;
    }
    for (; [args hasCurrent]; [args next]) {
        [stream writeObject: @", "];
        if (_skipCheck[idx]) {
            [stream writeObject: @"UNCHECKED"];
        } else {
            [stream writeObject: [args current]];
        }
        ++idx;
    }
    if (![selString hasSuffix: @":"]) {
        [stream writeByte: ' '];
        [stream writeObject: [selArray lastObject]];
    }

    unsigned int used = 0;
    unsigned int count = 0;
    BOOL unlimitedCount = NO;
    BOOL uncheckedCount = NO;
    if (_unexpected) {
        used = 1;
        count = 0;
    } else {
        TMockResult *result = _results;
        while (result != NULL) {
            used += result->used;
            if (!unlimitedCount && !uncheckedCount) {
                count += result->count;
                if (result->count == TUNIT_UNLIMITEDCALLCOUNT) {
                    unlimitedCount = YES;
                }
                if (result->count == TUNIT_UNCHECKEDCALLCOUNT) {
                    uncheckedCount = YES;
                }
            }
            result = result->next;
        }
    }
    [stream writeFormat: @"] (%u/", used];
    if (uncheckedCount) {
        [stream writeObject: @"unchecked"];
    } else if (unlimitedCount) {
        [stream writeObject: @"unlimited"];
    } else {
        [stream writeFormat: @"%u", count];
    }
    if (_file != NULL) {
        [stream writeFormat: @", expected at %s:%d", _file, _line];
    }
    [stream writeObject: @")"];
}


- (TMockMessage *)checkForInvocation: (TInvocation *)invocation
        addSimilarityTo: (TMutableArray *)similars
{
    if ([self isForSel: [invocation selector] andReceiver: [invocation target]]) {
        if ([self isForInvocation: invocation]) {
            if ([self hasPendingResults]) {
                id firstOrdered = [__orderedMessages firstObject];
                if ([[self class] consumeIfOrdered: self]) {
                    return self;
                } else if ([firstOrdered isForInvocation: invocation]
                        && [[self class] consumeIfOrdered: firstOrdered]) {
                    return firstOrdered;
                } else {
                    @throw [TTestException
                            exceptionWithFormat: @"Ordered message %@ was send out of order", self];
                }
            } else if ([self wantsNotToBeCalled]) {
                @throw [TTestException
                        exceptionWithFormat: @"Message %@ which should not be sent was sent", self];
            } else {
                [similars addObject: self];
            }
        } else {
            [similars addObject: self];
        }
    }
    return nil;
}


- ordered
{
    if (_lastResult->count == 0) {
        @throw [TTestException exceptionWithFormat: @"Unexpected message %@ cannot be ordered", self];
    }
    if (![self wantsCallCountChecking]) {
        @throw [TTestException exceptionWithFormat: @"Stubbed message %@ cannot be ordered", self];
    }
    if ([self hasUnlimitedCallCount]) {
        @throw [TTestException exceptionWithFormat: @"Unlimited message %@ cannot be ordered", self];
    }
    [[self class] addOrderedMessage: self];
    _isOrdered = YES;
    return nil;
}


- (void)setLocation: (const char *)file : (int)line
{
    _file = file;
    _line = line;
}


@end

