//
// (C) Copyright Tilo Prütz
//

#include "TUnit/TMockController.h"

#pragma .h #include <TFoundation/TFoundation.h>

#pragma .h @class TMock, TMockMessage;

#include <objc/objc-api.h>

#include "TUnit/TMock.h"
#include "TUnit/TMockMessage.h"
#include "TUnit/TTestException.h"


#pragma .h typedef struct _TMockList {
#pragma .h     TMock *mock;
#pragma .h     unsigned int retainCount;
#pragma .h     struct _TMockList *prev;
#pragma .h     struct _TMockList *next;
#pragma .h } TMockList;

#pragma .h #define verifyMocks verifyMocksAt: __FILE__ : __LINE__


@implementation TMockController:TObject
{
    TMutableArray *_messages;
    BOOL _isRecording;
    BOOL _isStrictReplaying;
    TMockList *_mocks;
    unsigned int _currentMessage;
}


+ mockController
{
    return [[[self alloc] init] autorelease];
}


- init
{
    [super init];
    _messages = [[TMutableArray array] retain];
    _isRecording = YES;
    _mocks = tAllocZero(sizeof(TMockList));
    return self;
}


- (void)__releaseMocks
{
    TMockList *cur = _mocks;

    do {
        TMockList *tmp = cur;

        if (cur->mock != nil) {
            [cur->mock->_name release];
            object_dispose(cur->mock);
        }
        cur = cur->prev;
        tFree(tmp);
    } while (cur != NULL);
}


- (void)dealloc
{
    [self __releaseMocks];
    [_messages release];
    [super dealloc];
}


+ (TString *)descriptionFor: (TMock *)mock
{
    TStringOutputStream *s = [TStringOutputStream stream];

    [s writeObject: @"Mock"];
    if (mock->_name != nil) {
        [s writeObject: @" with name '"];
        [s writeObject: mock->_name];
        [s writeByte: '\''];
    }
    [s writeObject: @" for"];

    if (mock->_class != Nil) {
        if (mock->_metaClass != Nil) {
            [s writeObject: @" meta class of"];
        }
        [s writeObject: @" class "];
        [s writeObject: [mock->_class className]];
    } else if (mock->_protocol != nil) {
        [s writeFormat: @" protocol %s", [mock->_protocol name]];
    }
    [s close];
    return [s targetString];
}


- (TMock *)__newMock
{
    TMock *mock = class_create_instance([TMock class]);
    TMockList *tmp = tAllocZero(sizeof(TMockList));

    mock->_mockListEntry = _mocks;
    _mocks->mock = mock;
    _mocks->retainCount = 1;
    _mocks->next = tmp;
    tmp->prev = _mocks;
    _mocks = tmp;
    mock->_controller = self;
    return mock;
}


- (TMock *)mockWithName: (TString *)name forClass: (Class)class
{
    TMock *mock = [self mockForClass: class];

    mock->_name = [name retain];
    return mock;
}


- (TMock *)mockWithName: (TString *)name forMetaClassOfClass: (Class)class
{
    TMock *mock = [self mockForMetaClassOfClass: class];

    mock->_name = [name retain];
    return mock;
}


- (TMock *)mockWithName: (TString *)name forProtocol: (Protocol *)protocol
{
    TMock *mock = [self mockForProtocol: protocol];

    mock->_name = [name retain];
    return mock;
}


- (TMock *)mockForClass: (Class)class
{
    TMock *mock = [self __newMock];

    mock->_class = class;
    return mock;
}


- (TMock *)mockForMetaClassOfClass: (Class)class
{
    TMock *mock = [self __newMock];

    mock->_class = class;
    mock->_metaClass = [class metaClass];
    return mock;
}


- (TMock *)mockForProtocol: (Protocol *)protocol
{
    TMock *mock = [self __newMock];

    mock->_protocol = protocol;
    return mock;
}


- (void)record
{
    _isRecording = YES;
}


- (void)replay
{
    _isRecording = NO;
    _isStrictReplaying = NO;
}


- (void)replayStrict
{
    _isRecording = NO;
    _isStrictReplaying = YES;
    _currentMessage = 0;
}


- (TMockMessage *)__mock: (TMock *)mock gotMsg: (SEL)sel
        withArgFrame: (arglist_t)argFrame
{
    TMockMessage *msg = nil;

    if (mock->_mockListEntry->retainCount == 0) {
        @throw [TTestException exceptionWithFormat:
                @"The mock '%@' was deallocated but got the message '%@'.",
                [[self class] descriptionFor: mock],
                [TUtils stringFromSelector: sel]];
    }
    if (sel == @selector(retain)) {
        mock->_mockListEntry->retainCount++;
    } else if (sel == @selector(release)) {
        mock->_mockListEntry->retainCount--;
    }
    if (_isRecording) {
        [_messages addObject: [TMockMessage mockMessageWithSel: sel
                receiver: mock andArgs: argFrame]];
    } else {
        TMutableArray *errors = [TMutableArray array];

        if (_isStrictReplaying) {
            if ([_messages count] > _currentMessage) {
                TMockMessage *aMsg = [_messages objectAtIndex: _currentMessage];

                if (![aMsg hasPendingResults] &&
                        [_messages count] > ++_currentMessage) {
                    aMsg = [_messages objectAtIndex: _currentMessage];
                }
                msg = [aMsg checkForSel: sel receiver: mock andArgs: argFrame addSimilarityTo: nil];
                if (msg == nil) {
                    [errors addObject: aMsg];
                }
            }
        } else {
            for (id <TIterator> i = [_messages iterator];
                    [i hasCurrent] && msg == nil; [i next]) {
                msg = [[i current] checkForSel: sel receiver: mock andArgs: argFrame
                        addSimilarityTo: errors];
            }
        }
        if (msg == nil) {
            TMockMessage *unexpected =
                    [TMockMessage unexpectedMockMessageWithSel: sel
                    receiver: mock andArgs: argFrame];

            if ([errors containsData]) {
                if (_isStrictReplaying) {
                    @throw [TTestException exceptionWithFormat:
                            @"Unexpected message: %@\nExpected: %@",
                            unexpected, [errors firstObject]];
                } else {
                    @throw [TTestException
                            exceptionWithFormat: @"Unexpected message: %@\n"
                            @"Expected similar messages:\n  %@", unexpected,
                            [errors componentsJoinedByString: @"\n  "]];
                }
            } else {
                @throw [TTestException exceptionWithFormat:
                        @"Unexpected message: %@", unexpected];
            }
        } else if ([msg exception] != nil) {
            @throw [msg exception];
        }
    }
    return msg;
}


#pragma .h #define GOT_MESSAGE_H(type, Type) - (type)mock: (TMock *)mock got##Type##Msg: (SEL)sel withArgFrame: (arglist_t)argFrame;


#define GOT_MESSAGE(type, Type) - (type)mock: (TMock *)mock got##Type##Msg: (SEL)sel withArgFrame: (arglist_t)argFrame\
{\
    return [[self __mock: mock gotMsg: sel withArgFrame: argFrame]\
            pop##Type##Result];\
}


#pragma .h GOT_MESSAGE_H(byte, Byte);
GOT_MESSAGE(byte, Byte);


#pragma .h GOT_MESSAGE_H(word, Word);
GOT_MESSAGE(word, Word);


#pragma .h GOT_MESSAGE_H(dword, Dword);
GOT_MESSAGE(dword, Dword);


#pragma .h GOT_MESSAGE_H(qword, Qword);
GOT_MESSAGE(qword, Qword);


#pragma .h GOT_MESSAGE_H(float, Float);
GOT_MESSAGE(float, Float);


#pragma .h GOT_MESSAGE_H(double, Double);
GOT_MESSAGE(double, Double);


- (void)mock: (TMock *)mock gotVoidMsg: (SEL)sel
        withArgFrame: (arglist_t)argFrame
{
    [[self __mock: mock gotMsg: sel withArgFrame: argFrame] popVoidResult];
}


- (retval_t)mock: (TMock *)mock gotBlockMsg: (SEL)sel
        withArgFrame: (arglist_t)argFrame
{
    return (retval_t)[[self __mock: mock gotMsg: sel withArgFrame: argFrame]
            popDwordResult];
}


#pragma .h #undef GOT_MESSAGE_H


- (void)setCallCount: (unsigned int)count
{
    [[_messages lastObject] setCallCount: count];
}


#pragma .h #define RESULT_CONVENIENCE_ACCESSOR_H(type, Type)\
#pragma .h - (void)set##Type##Result: (type)result\
#pragma .h         andCallCount: (unsigned int)count;\
#pragma .h - (void)expect: (type)dummy with##Type##Result: (type)result;\
#pragma .h - (void)expect: (type)dummy with##Type##Result: (type)result\
#pragma .h         andCallCount: (unsigned int)count;\
#pragma .h - (void)stub: (type)dummy with##Type##Result: (type)result;

#pragma .h #define RESULT_ACCESSOR_H(type, Type)\
#pragma .h - (void)set##Type##Result: (type)result;\
#pragma .h RESULT_CONVENIENCE_ACCESSOR_H(type, Type)

#define RESULT_CONVENIENCE_ACCESSOR(type, Type) -\
 (void)set##Type##Result: (type)result andCallCount: (unsigned int)count\
{\
    [self set##Type##Result: result];\
    [self setCallCount: count];\
}; - (void)expect: (type)dummy with##Type##Result: (type)result\
{\
    [self set##Type##Result: result];\
}; - (void)expect: (type)dummy with##Type##Result: (type)result\
        andCallCount: (unsigned int)count\
{\
    [self set##Type##Result: result];\
    [self setCallCount: count];\
}; - (void)stub: (type)dummy with##Type##Result: (type)result\
{\
    [self set##Type##Result: result];\
    [self setCallCount: TUNIT_UNCHECKEDCALLCOUNT];\
}

#define RESULT_ACCESSOR(type, Type, pushType, castType) - (void)set##Type##Result: (type)result\
{\
    [[_messages lastObject] push##pushType##Result: (castType)result];\
}; RESULT_CONVENIENCE_ACCESSOR(type, Type)


- (void)setResult: result
{
    [[_messages lastObject] pushDwordResult: (dword)result];
}


#pragma .h RESULT_CONVENIENCE_ACCESSOR_H(id,);
RESULT_CONVENIENCE_ACCESSOR(id,);


#pragma .h RESULT_ACCESSOR_H(char, Char);
RESULT_ACCESSOR(char, Char, Byte, byte);


#pragma .h RESULT_ACCESSOR_H(short, Short);
RESULT_ACCESSOR(short, Short, Word, word);


#pragma .h RESULT_ACCESSOR_H(int, Int);
RESULT_ACCESSOR(int, Int, Dword, dword);


// TODO Bei 64-bit-Maschinen Qword
#pragma .h RESULT_ACCESSOR_H(const unsigned char *, UCPtr);
RESULT_ACCESSOR(const unsigned char *, UCPtr, Dword, dword);


#pragma .h RESULT_ACCESSOR_H(long long, LongLong);
RESULT_ACCESSOR(long long, LongLong, Qword, qword);


#pragma .h RESULT_ACCESSOR_H(float, Float);
RESULT_ACCESSOR(float, Float, Float, float);


#pragma .h RESULT_ACCESSOR_H(double, Double);
RESULT_ACCESSOR(double, Double, Double, double);


#pragma .h RESULT_ACCESSOR_H(BOOL, Bool);
RESULT_ACCESSOR(BOOL, Bool, Byte, byte);


#pragma .h #undef RESULT_ACCESSOR_H
#pragma .h #undef RESULT_CONVENIENCE_ACCESSOR_H


- (void)setException: e
{
    [[_messages lastObject] setException: e];
}


- skipParameterCheck: (unsigned int)index
{
    return [[_messages lastObject] skipParameterCheck: index];
}


- (void)verifyMocksAt: (const char *)file : (int)line
{
    TMutableArray *pendingMessages = [TMutableArray array];

    for (id <TIterator> i = [_messages iterator]; [i hasCurrent]; [i next]) {
        TMockMessage *msg = [i current];

        if ([msg wantsCallCountChecking] && [msg hasPendingResults] &&
                (![msg hasUnlimitedCallCount] || ![msg wasEverSent])) {
            [pendingMessages addObject: msg];
        }
    }
    [_messages removeAllObjects];
    if ([pendingMessages containsData]) {
        @throw [TTestException exceptionAt: file : line withFormat:
                @"The following messages were not sent to mock objects: %@",
                pendingMessages];
    }
}


@end
