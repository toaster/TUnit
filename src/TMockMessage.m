//
// (C) Copyright Tilo Prütz
//

#include "TUnit/TMockMessage.h"

#pragma .h #include <TFoundation/TFoundation.h>

#pragma .h #include "TUnit/TMock.h"

#include <math.h>
#include <objc/objc-api.h>
#include <objc/encoding.h>

#include "TUnit/TTestException.h"

#pragma .h #define TUNIT_UNLIMITEDCALLCOUNT 0xFFFFFFFE
#pragma .h #define TUNIT_UNCHECKEDCALLCOUNT 0xFFFFFFFF

#pragma .h typedef struct _TMockResult TMockResult;
#pragma .h typedef union _TMockVariable TMockVariable;

union _TMockVariable {
    byte aByte;
    word aWord;
    dword aDword;
    qword aQword;
    float aFloat;
    double aDouble;
    TString *aCharArray;
};

struct _TMockResult {
    TMockVariable value;
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
}


static inline TString *_byteString(byte aByte)
{
    return [TString stringWithFormat: @"(char)0x%02x", aByte];
}


static inline TString *_wordString(word aWord, BOOL isSigned)
{
    return [TString stringWithFormat: (isSigned ? @"(short)%d" : @"(short)%u"),
            aWord];
}


static inline TString *_dwordString(dword aDword, char type)
{
    TString *result = nil;

    switch (type) {
        case _C_CLASS:
            result = [(Class)aDword className];
            break;
        case _C_PTR:
        case _C_ATOM:
        case _C_CHARPTR:
            result = [TString stringWithFormat: @"0x%08x", aDword];
            break;
        case _C_INT:
        case _C_LNG:
            result = [TString stringWithFormat: @"%i", aDword];
            break;
        case _C_UINT:
        case _C_ULNG:
            result = [TString stringWithFormat: @"%u", aDword];
            break;
        default:
            // never happens
            break;
    }
    return result;
}


static inline TString *_qwordString(word aQword, BOOL isSigned)
{
    return [TString stringWithFormat: (isSigned ? @"(long long)%lld" :
            @"(long long)%llu"), aQword];
}


static inline TString *_floatString(float aFloat)
{
    return [TString stringWithFormat: @"(float)%f", aFloat];
}


static inline TString *_doubleString(double aDouble)
{
    return [TString stringWithFormat: @"(double)%f", aDouble];
}


static inline BOOL _isTMock(id object)
{
    return [TMock class] == object_get_class(object);
}


static inline TString *_idString(id object)
{
    if (_isTMock(object)) {
        return [TString stringWithFormat: @"<%@>",
               [TMockController descriptionFor: (TMock *)object]];
// FIXME: kommt von ip - testen & Test bauen, ob das irgendwie sinnvoll ist, oder ob die
// Default-Ausgabe schöner ist.
//    } else if ([Protocol class] == class) {
//        return [TString stringWithFormat: @"@protocol(%@)", [(Protocol *)object name]];
    } else {
        return [TString stringWithFormat: @"<%@ %s %@>", [object className],
                object_is_instance(object) ? "instance" : "class", object];
    }
}


static inline TString *_charArrayString(unsigned char *array, unsigned size)
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
    return [TString stringWithFormat: @"@selector(%@)",
            [TUtils stringFromSelector: sel]];
}


static inline int _parameterValues(id receiver, SEL sel, arglist_t argFrame,
        TMockVariable **values, TMutableArray *argStrings, BOOL validate,
        int argCount, TMockVariable *args, BOOL *skipCheck)
{
    int result = 0;
    BOOL messageIsValid = NO;

    struct objc_method_description *methodDescription = NULL;
    if (_isTMock(receiver)) {
        TMock *mock = (TMock *)receiver;
        if (mock->_metaClass != Nil) {
            methodDescription = (struct objc_method_description *)
                    class_get_instance_method(mock->_metaClass, sel);
        } else if (mock->_class != Nil) {
            methodDescription = (struct objc_method_description *)
                    class_get_instance_method(mock->_class, sel);
        } else if (mock->_protocol != NULL) {
            methodDescription = [mock->_protocol descriptionForInstanceMethod: sel];
            if (methodDescription == NULL) {
                methodDescription = [mock->_protocol descriptionForClassMethod: sel];
            }
        }
    } else if (object_is_instance(receiver)) {
        methodDescription = (struct objc_method_description *)class_get_instance_method(
                object_get_class(receiver), sel);
    } else {
        methodDescription = (struct objc_method_description *)class_get_class_method(
                class_get_meta_class(receiver), sel);
    }
    if (methodDescription != NULL) {
        const char *type = methodDescription->types;
        int i = 0;

        messageIsValid = YES;
        while (type && *type) {
            type = objc_skip_argspec(type);
            ++i;
        }
        result = i - 1;
        if (i < 0) result = 0;
        if (values != NULL) {
            *values = (TMockVariable *)tAllocZero(result *
                    sizeof(TMockVariable));
        }
        type = methodDescription->types;
        i = 0;
        char *arg;
        for (arg = method_get_next_argument(argFrame, &type);
                arg != NULL; arg = method_get_next_argument(argFrame, &type)) {
            BOOL isValid = argCount > i;

            type = objc_skip_type_qualifiers(type);
            switch (*type) {
                // Das paßt für i386 -> andere Architekturen -> feinere
                // Behandlung
                case _C_CHR:
                case _C_UCHR:
                    [argStrings addObject: _byteString(*arg)];
                    if (!validate) {
                        (*values)[i].aByte = *arg;
                    } else if (isValid) {
                        isValid = (*arg == args[i].aByte);
                    }
                    break;
                case _C_SHT:
                case _C_USHT:
                    [argStrings addObject: _wordString(*((word *)arg),
                            *type == _C_SHT)];
                    if (!validate) {
                        (*values)[i].aWord = *((word *)arg);
                    } else if (isValid) {
                        isValid = (*((word *)arg) == args[i].aWord);
                    }
                    break;
                case _C_ID:
                    if (i > 0) {
                        [argStrings addObject: _idString(*((id *)arg))];
                    }
                    if (!validate) {
                        (*values)[i].aDword = *((dword *)arg);
                    } else if (isValid && i > 0) {
                        // arg 0 is the receiver -> maybe a mock that must not get a message here.
                        // It's validity has already been approved.
                        id value = *((id *)arg);
                        id expectedValue = (id)(args[i].aDword);

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
                            (*values)[i].aDword = *((dword *)arg);
                        } else if (isValid) {
                            isValid = sel_eq(*((SEL *)arg), (SEL)(args[i].aDword));
                        }
                    }
                    break;
                case _C_CLASS:
                case _C_PTR:
                case _C_ATOM:
                case _C_CHARPTR:
                case _C_INT:
                case _C_UINT:
                case _C_LNG:
                case _C_ULNG:
                    [argStrings addObject: _dwordString(*((dword *)arg),
                            *type)];
                    if (!validate) {
                        (*values)[i].aDword = *((dword *)arg);
                    } else if (isValid && i > 1) {
                        isValid = (*((dword *)arg) == args[i].aDword);
                    }
                    break;
                case _C_LNG_LNG:
                case _C_ULNG_LNG:
                    [argStrings addObject: _qwordString(*((qword *)arg),
                            *type == _C_LNG_LNG)];
                    if (!validate) {
                        (*values)[i].aQword = *((qword *)arg);
                    } else if (isValid) {
                        isValid = (*((qword *)arg) == args[i].aQword);
                    }
                    break;
                case _C_FLT:
                    [argStrings addObject: _floatString(*((float *)arg))];
                    if (!validate) {
                        (*values)[i].aFloat = *((float *)arg);
                    } else if (isValid) {
                        isValid = (*((float *)arg) == args[i].aFloat);
                    }
                    break;
                case _C_DBL:
                    [argStrings addObject: _doubleString(*((double *)arg))];
                    if (!validate) {
                        (*values)[i].aDouble = *((double *)arg);
                    } else if (isValid) {
                        isValid = (*((double *)arg) == args[i].aDouble);
                    }
                    break;
                case _C_ARY_B:
                    {
                        char *end = strchr(type, _C_ARY_E);
                        char elementType = *(end - 1);
                        if (elementType == _C_CHR || elementType == _C_UCHR) {
                            unsigned arraySize = 0;
                            for (int j = 0; j < end - type - 2; ++j) {
                                arraySize += (*(end - 2 - j) - '0') * pow(10, j);
                            }
                            [argStrings addObject:
                                    _charArrayString(*(unsigned char **)arg, arraySize)];
                            TString *value = [TString stringWithCString: *(char **)arg
                                    length: arraySize];
                            if (!validate) {
                                (*values)[i].aCharArray = value;
                            } else {
                                isValid = [args[i].aCharArray isEqual: value];
                            }
                            break;
                        } else {
                            // Other array types are not supported yet.
                        }
                    }
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
                    @throw [TTestException
                            exceptionWithFormat: @"Invalid parameter type "
                            @"'%c' for forwarded message '%@' parameter %d.",
                            type, [TUtils stringFromSelector: sel], i];
                    isValid = NO;
                    break;
            }
            if (validate && !isValid && skipCheck[i]) {
                isValid = YES;
            }
            if (validate && !isValid) {
                messageIsValid = NO;
            }
            ++i;
        }
    } else if (values != NULL) {
        *values = NULL;
    }
    if (validate && argCount != result) {
        @throw [TTestException exceptionWithFormat: @"Invalid argument count "
                @"%d (should be %d) for message '%@' to %@.", result, argCount,
                [TUtils stringFromSelector: sel], _idString(receiver)];
    }
    return validate ? messageIsValid : result;
}


+ mockMessageWithSel: (SEL)sel receiver: receiver andArgs: (arglist_t)argFrame
{
    return [[[self alloc] initWithSel: sel receiver: receiver andArgs: argFrame] autorelease];
}


+ unexpectedMockMessageWithSel: (SEL)sel receiver: receiver andArgs: (arglist_t)argFrame
{
    TMockMessage *msg = [[[self alloc] initWithSel: sel receiver: receiver
            andArgs: argFrame] autorelease];

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


- initWithSel: (SEL)sel receiver: receiver andArgs: (arglist_t)argFrame
{
    [self init];
    _sel = sel;
    _receiver = receiver;
    _argStrings = [[TMutableArray array] retain];
    _argCount = _parameterValues(receiver, sel, argFrame, &_args, _argStrings,
            NO, 0, NULL, NULL);
    if (_argCount > 0) {
        _skipCheck = (BOOL *)tAllocZero(_argCount * sizeof(BOOL));
    }
    [self __newResult];
    _overrideResult = YES;
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


#pragma .h #define RESULT_ACCESSOR_H(type, Type) - (void)push##Type##Result: (type)result; - (type)pop##Type##Result;

#define RESULT_ACCESSOR(type, Type) - (void)push##Type##Result: (type)result\
{\
    [self __newResult];\
    _lastResult->value.a##Type = result;\
}; - (type)pop##Type##Result\
{\
    type result = (type)0;\
    TMockResult *r = [self __popResult];\
\
    if (r != NULL) {\
        result = r->value.a##Type;\
    }\
    return result;\
}


- (void)popVoidResult
{
    [self __popResult];
}


#pragma .h RESULT_ACCESSOR_H(byte, Byte);
RESULT_ACCESSOR(byte, Byte);


#pragma .h RESULT_ACCESSOR_H(word, Word);
RESULT_ACCESSOR(word, Word);


#pragma .h RESULT_ACCESSOR_H(dword, Dword);
RESULT_ACCESSOR(dword, Dword);


#pragma .h RESULT_ACCESSOR_H(qword, Qword);
RESULT_ACCESSOR(qword, Qword);


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
            (_nextResult->count == TUNIT_UNLIMITEDCALLCOUNT ||
            _nextResult->count == TUNIT_UNCHECKEDCALLCOUNT);
}


- (BOOL)wantsCallCountChecking
{
    return _nextResult != NULL &&
            _nextResult->count != TUNIT_UNCHECKEDCALLCOUNT;
}


- (BOOL)wasEverSent
{
    return _results != NULL && _results->used > 0;
}


- (BOOL)isForSel: (SEL)sel andReceiver: receiver
{
    return sel_eq(_sel, sel) && _receiver == receiver;
}


- (BOOL)isForArgs: (arglist_t)argFrame
{
    return _parameterValues(_receiver, _sel, argFrame, NULL, nil, YES,
            _argCount, _args, _skipCheck) != 0;
}


- (BOOL)isForSel: (SEL)sel receiver: receiver andArgs: (arglist_t)argFrame
{
    return [self isForSel: sel andReceiver: receiver] && [self isForArgs: argFrame];
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


- (TMockMessage *)checkForSel: (SEL)sel receiver: rcv andArgs: (arglist_t)argFrame
        addSimilarityTo: (TMutableArray *)similars
{
    if ([self isForSel: sel andReceiver: rcv]) {
        if ([self isForArgs: argFrame]) {
            if ([self hasPendingResults]) {
                id firstOrdered = [__orderedMessages firstObject];
                if ([[self class] consumeIfOrdered: self]) {
                    return self;
                } else if ([firstOrdered isForSel: sel andReceiver: rcv]
                        && [firstOrdered isForArgs: argFrame]
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
        @throw [TTestException exceptionWithFormat: @"Unexpected message %@ cannot be ordered",
                self];
    }
    if (![self wantsCallCountChecking]) {
        @throw [TTestException exceptionWithFormat: @"Stubbed message %@ cannot be ordered", self];
    }
    if ([self hasUnlimitedCallCount]) {
        @throw [TTestException exceptionWithFormat: @"Unlimited message %@ cannot be ordered",
                self];
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

