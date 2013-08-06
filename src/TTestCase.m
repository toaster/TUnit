//
// (C) Copyright Tilo Prütz
//

#include "TUnit/TTestCase.h"

#pragma .h #include <TFoundation/TFoundation.h>

#pragma .h #include <sys/resource.h>


#include <objc/objc.h>
#include <objc/runtime.h>
#include <string.h>

#include "TUnit/ProtocolTester.h"
#include "TUnit/TTestException.h"
#include "TUnit/TMockController.h"
#include "TUnit/TMockMessage.h"
#include "TUnit/TObject.Mock.h"


#pragma .h typedef void(TUnitCallBack)();
#pragma .h extern TUnitCallBack *tUnitBeforeSetUp;

TUnitCallBack *tUnitBeforeSetUp = NULL;


#pragma .h #define _ASSERT(sel) [self sel file: __FILE__ line: __LINE__]; [self clearHint];

#pragma .h #define ASSERTEQUALSINT(int1, int2) _ASSERT(_assertInt: int1 equalsInt: int2)

#pragma .h #define ASSERTEQUALSUINT(int1, int2) _ASSERT(_assertUInt: int1 equalsUInt: int2)

#pragma .h #define ASSERTISGREATERTHANINT(int1, int2) _ASSERT(_assertInt: int2 isGreaterThan: int1)

#pragma .h #define ASSERTISLESSTHANINT(int1, int2) _ASSERT(_assertInt: int2 isLessThan: int1)

#pragma .h #define ASSERTEQUALS(obj1, obj2) _ASSERT(_assert: obj1 equals: obj2)

#pragma .h #define ASSERTNOTEQUALS(obj1, obj2) _ASSERT(_assert: obj1 notEquals: obj2)

#pragma .h #define ASSERTIDENTICAL(obj1, obj2) _ASSERT(_assert: obj1 isIdenticalTo: obj2)

#pragma .h #define ASSERT(x) _ASSERT(_assert: @#x isTrue: x shouldBeFalse: NO)

#pragma .h #define ASSERTFALSE(x) _ASSERT(_assert: @#x isTrue: x shouldBeFalse: YES)

#pragma .h #define ASSERTNIL(x) ASSERT((x) == nil);

#pragma .h #define ASSERTNOTNIL(x) ASSERT((x) != nil);

#pragma .h #define ASSERTKINDOF(expectedClass, obj) _ASSERT(_assert: obj isKindOf: expectedClass)

#pragma .h #define ASSERTLISTCONTENTSEQUAL(expected, got)\
#pragma .h         _ASSERT(_assertList: got containsEqualElementsAs: expected)

#pragma .h #define ASSERTLISTCONTAINS(expected, got)\
#pragma .h         _ASSERT(_assertList: got containsElementsFrom: expected)

#pragma .h #define ASSERTLISTDOESNOTCONTAIN(expected, got)\
#pragma .h         _ASSERT(_assertList: got doesNotContainElementsFrom: expected)

#pragma .h #define ASSERTSUBSTRING(expected, got) _ASSERT(_assert: got hasSubstring: expected)

#pragma .h #define ASSERTMATCHES(expected, result) _ASSERT(_assert: result matches: expected)

#pragma .h #define ASSERTISFASTERTHAN(fast, slow, howMany) {\
#pragma .h     long long __fastTime__ = [TTime currentTimeMillis];\
#pragma .h \
#pragma .h     for (int __i__ = 0; __i__ < howMany; ++__i__) {\
#pragma .h         fast;\
#pragma .h     }\
#pragma .h     __fastTime__ = [TTime currentTimeMillis] - __fastTime__;\
#pragma .h \
#pragma .h     long long __slowTime__ = [TTime currentTimeMillis];\
#pragma .h \
#pragma .h     for (int __i__ = 0; __i__ < howMany; ++__i__) {\
#pragma .h         slow;\
#pragma .h     }\
#pragma .h     __slowTime__ = [TTime currentTimeMillis] - __slowTime__;\
#pragma .h     ASSERTISLESSTHANINT(__slowTime__, __fastTime__);\
#pragma .h }

#pragma .h #define ASSERTISFAST(expectedMaxMilliSeconds, method, howMany) {\
#pragma .h     long long __expected__ = (long long)expectedMaxMilliSeconds;\
#pragma .h     struct rusage __usage__;\
#pragma .h     long long __before__;\
#pragma .h     long long __after__;\
#pragma .h     getrusage(RUSAGE_SELF, &__usage__);\
#pragma .h     __before__ = (long long)__usage__.ru_utime.tv_sec * 1000000 +\
#pragma .h             (long long)__usage__.ru_utime.tv_usec;\
#pragma .h \
#pragma .h     for (int __i__ = 0; __i__ < howMany; ++__i__) {\
#pragma .h         method;\
#pragma .h     }\
#pragma .h     getrusage(RUSAGE_SELF, &__usage__);\
#pragma .h     __after__ = (long long)__usage__.ru_utime.tv_sec * 1000000 +\
#pragma .h             (long long)__usage__.ru_utime.tv_usec;\
#pragma .h \
#pragma .h     ASSERTISLESSTHANINT(__expected__, (__after__ - __before__) / 1000);\
#pragma .h }

#pragma .h #define _FAIL(eClass, eId, expectedE, x, code...) {\
#pragma .h     eClass e = nil;\
#pragma .h     id unexpectedException = nil;\
#pragma .h \
#pragma .h     @try {\
#pragma .h         x;\
#pragma .h     } @catch(eClass caught) {\
#pragma .h         e = caught;\
#pragma .h     } @catch(id u) {\
#pragma .h         unexpectedException = u;\
#pragma .h     }\
#pragma .h     if (e == nil && unexpectedException == nil) {\
#pragma .h         @throw [TTestException exceptionAt: __FILE__ : __LINE__ \
#pragma .h                 withMessage: @#x @" did not fail"];\
#pragma .h     } else if (expectedE != nil && ![expectedE isEqual: e]) {\
#pragma .h         @throw [TTestException exceptionAt: __FILE__ : __LINE__ \
#pragma .h                 withFormat: @#x @" failed with unexpected exception %@ instead of %@",\
#pragma .h                 e, expectedE];\
#pragma .h     } else if (unexpectedException != nil) {\
#pragma .h         @throw [TTestException exceptionAt: __FILE__ : __LINE__ \
#pragma .h                 withFormat: @#x @" failed with unexpected exception %@ instead of %@",\
#pragma .h                 unexpectedException, @#eClass];\
/*FIXME IP #pragma .h     } else if (eId != 0 && eId != [(id)e errorId]) {\
 *FIXME IP #pragma .h         @throw [TTestException exceptionAt: __FILE__ : __LINE__ \
 *FIXME IP #pragma .h                 withFormat: @#x@" failed with unexpected exception ID %d instead of %d",\
 *FIXME IP #pragma .h                 [(id)e errorId], eId];*/\
#pragma .h     }\
#pragma .h     code;\
#pragma .h }


#pragma .h #define FAIL(x...) _FAIL(id, 0, nil, x)

#pragma .h #define FAIL_WITH_CLASS(exceptionClass, x...)\
#pragma .h         _FAIL(exceptionClass *, 0, nil, x)

#pragma .h #define FAIL_WITH_CLASS_AND_ID(exceptionClass, exceptionId, x...)\
#pragma .h         _FAIL(exceptionClass *, exceptionId, nil, x)

#pragma .h #define FAIL_WITH_EQUAL(expectedException, x...)\
#pragma .h         _FAIL(id, 0, expectedException, x)


static TString *__baseDir = nil;
static TString *__dataDir = nil;
static TString *__package = nil;


@implementation TTestCase:TObject
{
    TString *_hint;
}


- (void)dealloc
{
    [_hint release];
    [super dealloc];
}


- (TString *)assertionMessage: (TString *)format, ...
{
    va_list args;
    va_start(args, format);
    TString *reason = [TString stringWithFormat: format andArgs: &args];
    va_end(args);
    TString *message = [TString stringWithFormat: @"Assertion failed: %@", reason];
    if (_hint != nil) {
        message = [TString stringWithFormat: @"%@ (%@)", message, _hint];
    }
    return message;
}


- (void)_assert: obj1 equals: obj2 file: (const char *)file line: (int)line
{
    if ((obj1 != nil || obj2 != nil) && ![obj1 isEqual: obj2]) {
        TString *msg = nil;
        if ([obj1 isKindOf: [TDictionary class]] && [obj2 isKindOf: [TDictionary class]]) {
            msg = [self _dictDiff: obj1 : obj2];
        }
        @throw [TTestException exceptionAt: file : line withMessage: [self assertionMessage:
                @"»%@« is not equal »%@«%s%@", obj1, obj2, msg != nil ? ":\n" : "", msg]];
    }
}


- (void)_assert: obj1 notEquals: obj2 file: (const char *)file line: (int)line
{
    if ((obj1 == nil && obj2 == nil) || [obj1 isEqual: obj2]) {
        @throw [TTestException exceptionAt: file : line
                withMessage: [self assertionMessage: @"»%@« is equal »%@«", obj1, obj2]];
    }
}


- (TString *)_dictDiff: (TDictionary *)dict1 : (TDictionary *)dict2
{
    TMutableArray *msgs = [TMutableArray array];
    TMutableArray *keys1 = [TMutableArray arrayWithArray: [dict1 allKeys]];
    TMutableArray *keys2 = [TMutableArray arrayWithArray: [dict2 allKeys]];

    for (id <TIterator> i = [dict1 keyIterator]; [i hasCurrent]; [i next]) {
        id key = [i current];
        id value1 = [dict1 objectForKey: key];
        id value2 = [dict2 objectForKey: key];
        if (value2 != nil) {
            if (![value1 isEqual: value2]) {
                TString *msg = nil;
                if ([value1 isKindOf: [TDictionary class]] &&
                        [value2 isKindOf: [TDictionary class]]) {
                    msg = [self _dictDiff: value1 : value2];
                }
                [msgs addObject: [TString stringWithFormat: @"%@: %@ != %@%s%@",
                        [self objDescription: key], [self _description: value1],
                        [self _description: value2], msg != nil ? ":\n" : "", msg]];
            }
            [keys1 removeObject: key];
            [keys2 removeObject: key];
        }
    }
    if ([keys1 containsData]) {
        [msgs addObject: [TString stringWithFormat: @"Only in expected dict: %@\n",
                [self objDescription:
                [keys1 arrayByFilteringWithObject: self andSelector: @selector(_description:)]]]];
    }
    if ([keys2 containsData]) {
        [msgs addObject: [TString stringWithFormat: @"Only in result dict: %@\n",
                [self objDescription:
                [keys2 arrayByFilteringWithObject: self andSelector: @selector(_description:)]]]];
    }
    return [msgs componentsJoinedByString: @"\n\n"];
}


- (TString *)_description: obj
{
    return [TString stringWithFormat: @"(%@) %@", [obj className], [self objDescription: obj]];
}


- objDescription: obj
{
    return object_getClass(obj) == [TMock class] ? (id)[TMockController descriptionFor: obj] : obj;
}


- (void)_assertInt: (int)int1 equalsInt: (int)int2 file: (const char *)file line: (int)line
{
    if (int1 != int2) {
        @throw [TTestException exceptionAt: file : line withMessage: [self assertionMessage:
                @"%d is not equal %d", int1, int2]];
    }
}


- (void)_assertUInt: (unsigned long)int1 equalsUInt: (unsigned long)int2
        file: (const char *)file line: (int)line
{
    if (int1 != int2) {
        @throw [TTestException exceptionAt: file : line withMessage: [self assertionMessage:
                @"%lu is not equal %lu", int1, int2]];
    }
}


- (void)_assertInt: (int)int1 isGreaterThan: (int)int2
        file: (const char *)file line: (int)line
{
    if (int1 <= int2) {
        @throw [TTestException exceptionAt: file : line withMessage: [self assertionMessage:
                @"%d is not greater than %d", int1, int2]];
    }
}


- (void)_assertInt: (int)int1 isLessThan: (int)int2
        file: (const char *)file line: (int)line
{
    if (int1 >= int2) {
        @throw [TTestException exceptionAt: file : line withMessage: [self assertionMessage:
                @"%d is not less than %d", int1, int2]];
    }
}


- (void)_assert: obj1 isIdenticalTo: obj2
        file: (const char *)file line: (int)line
{
    if (obj1 != obj2) {
        @throw [TTestException exceptionAt: file : line
                withMessage: [self assertionMessage: @"%p is not identical to %p", obj1, obj2]];
    }
}


- (void)_assert: (TString *)expression isTrue: (BOOL)isTrue
        shouldBeFalse: (BOOL)shouldBeFalse file: (const char *)file
        line: (int)line
{
    if ((!isTrue && !shouldBeFalse) || (isTrue && shouldBeFalse)) {
        @throw [TTestException exceptionAt: file : line withMessage: [self assertionMessage:
                @"%@ is not %s", expression, shouldBeFalse ? "false" : "true"]];
    }
}


- (void)_assert: obj isKindOf: (Class)expectedClass
        file: (const char *)file line: (int)line
{
    if (![obj isKindOf: expectedClass]) {
        @throw [TTestException exceptionAt: file : line withMessage: [self assertionMessage:
                @"object's class %@ is not kind of expected class %@",
                [obj className], [expectedClass className]]];
    }
}


- (void)_assertList: (TArray *)got containsElementsFrom: (TArray *)expected
        file: (const char *)file line: (int)line
{
    [self _assertList: got containsElementsFrom: expected failOnUnexpected: NO
            file: file line: line];
}


- (void)_assertList: (TArray *)got containsEqualElementsAs: (TArray *)expected
        file: (const char *)file line: (int)line
{
    [self _assertList: got containsElementsFrom: expected failOnUnexpected: YES
            file: file line: line];
}


- (void)_assertList: (TArray *)got containsElementsFrom: (TArray *)expected
        failOnUnexpected: (BOOL)failOnUnexpected file: (const char *)file line: (int)line
{
    id unexpected = [TMutableArray array];
    if (failOnUnexpected) {
        for (id <TIterator> i = [got iterator]; [i hasCurrent]; [i next]) {
            if (![expected containsObject: [i current]]) {
                [unexpected addObject: [i current]];
            }
        }
    }
    id missed = [TMutableArray array];
    for (id <TIterator> i = [expected iterator]; [i hasCurrent]; [i next]) {
        if (![got containsObject: [i current]]) {
            [missed addObject: [i current]];
        }
    }
    if ([unexpected count] > 0 || [missed count] > 0) {
        @throw [TTestException exceptionAt: file : line withMessage: [self assertionMessage:
                @"%@ does not contain the same elements as the expected list %@:%s%@%s%@",
                got, expected,
                [unexpected count] > 0 ? "\nUnexpected: " : "",
                [unexpected count] > 0 ? unexpected : nil,
                [missed count] > 0 ? "\nMissed: " : "",
                [missed count] > 0 ? missed : nil]];
    }
}


- (void)_assertList: (TArray *)got doesNotContainElementsFrom: (TArray *)forbidden
        file: (const char *)file line: (int)line
{
    id unexpected = [TMutableArray array];
    for (id <TIterator> i = [got iterator]; [i hasCurrent]; [i next]) {
        if ([forbidden containsObject: [i current]]) {
            [unexpected addObject: [i current]];
        }
    }
    if ([unexpected count] > 0) {
        @throw [TTestException exceptionAt: file : line withMessage: [self assertionMessage:
                @"%@ does contain the forbidden elements %@", got, unexpected]];
    }
}


- (void)_assert: obj hasSubstring: (TString *)string file: (const char *)file line: (int)line
{
    if (obj == nil || string == nil ||
            strstr([[obj stringValue] cString], [string cString]) == NULL) {
        @throw [TTestException exceptionAt: file : line withMessage: [self assertionMessage:
                @"%@ does not have the substring %@", obj, string]];
    }
}


- (void)_assert: (TString *)value matches: (TString *)expected
        file: (const char *)file line: (int)line
{
    if (![value matches: expected]) {
        @throw [TTestException exceptionAt: file : line withMessage: [self assertionMessage:
                @"value %@ does not match expression %@.", value, expected]];
    }
}


- (void)setHint: (TString *)hint
{
    if (_hint != hint) {
        [_hint release];
        _hint = [hint retain];
    }
}


- (void)clearHint
{
    [_hint release];
    _hint = nil;
}


- (void)beforeAll
{
}


- (void)before
{
    [self setUp];
}


- (void)setUp
{
    [self prepare];
}


- (void)prepare
{
}


- (void)after
{
    [self tearDown];
}


- (void)tearDown
{
    [self cleanup];
}


- (void)cleanup
{
}


- (void)afterAll
{
}


+ (void)noTest
{
    @throw [TTestException exceptionAt: __FILE__ : __LINE__ withMessage:
            @"TTestCase runs selectors without prefix 'test'."];
}


- (void)noTest
{
    @throw [TTestException exceptionAt: __FILE__ : __LINE__ withMessage:
            @"TTestCase runs selectors without prefix 'test'."];
}


- (void)printRunning: (Class)classUnderTest
{
    [TUserIO print: @"objc."];
    if ([__package containsData]) {
        [TUserIO print: __package];
        [TUserIO print: @"."];
    }
    [TUserIO print: [self className]];
    if (classUnderTest) {
        [TUserIO print: @"("];
        [TUserIO print: [classUnderTest className]];
        [TUserIO print: @")"];
    }
    [TUserIO print: @" "];
    [TUserIO flush];
}


- (int)run: (TString *)methodFilter for: (Class)classUnderTest
{
    int result = 0;
    TAutoreleasePool *pool = [[TAutoreleasePool alloc] init];
    int testCount = 0;
    [self printRunning: classUnderTest];
    TMutableArray *failures = [TMutableArray array];
    id error = nil;
    @try {
        [self clearHint];
        [self beforeAll];

        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList([self class], &methodCount);
        if (methods) {
            for (unsigned int i = 0; i < methodCount; i++) {
                TAutoreleasePool *testPool = [[TAutoreleasePool alloc] init];
                SEL sel = method_getName(methods[i]);
                TString *method = [TUtils stringFromSelector: sel];

                if (([method hasPrefix: @"test"] || [method hasPrefix: @"itShould"]) &&
                        (nil == methodFilter || [method matches: methodFilter]) &&
                        ![method matches: @"Broken$"]) {
                    TStack *exceptions = [TStack stack];
                    ++testCount;
                    @try {
                        [self clearHint];
                        [TMockMessage cleanupOrderedMessages];
                        if (tUnitBeforeSetUp != NULL) {
                            tUnitBeforeSetUp();
                        }
                        [self before];
                        @try {
                            [self perform: sel];
                            [TUserIO print: @"."];
                            [TUserIO flush];
                        } @catch (id e) {
                            [exceptions push: e];
                        } @finally {
                            @try {
                                verifyAndCleanupMocks();
                            } @catch (id e) {
                                [exceptions push: e];
                            } @finally {
                                [self after];
                            }
                        }
                    } @catch (id e) {
                        [exceptions push: e];
                    }
                    if ([exceptions containsData]) {
                        [TUserIO print: @"F"];
                        [TUserIO flush];
                        [failures addObject: A(method, exceptions)];
                    }
                }
                [testPool release];
            }
            free(methods);
        }
        [self afterAll];
    } @catch (id e) {
        error = e;
    }
    [TUserIO println: (![failures containsData] && error == nil) ? @" OK" : @" FAILED"];
    for (id <TIterator> i = [failures iterator]; [i hasCurrent]; [i next]) {
        TArray *entry = [i current];
        TString *method = [entry objectAtIndex: 0];
        TStack *exceptions = [entry objectAtIndex: 1];
        [TUserIO eprintln: @"ERROR: Test %@:%@ failed - %@",
                [self className], method, [exceptions pop]];
        while ([exceptions containsData]) {
            [TUserIO eprintln: @"Root cause:\n%@", [exceptions pop]];
        }
    }
    result = [failures count];
    [TUserIO eprintln: @"%d test%s, %d failure%s", testCount, testCount != 1 ? "s" : "",
            result, result != 1 ? "s" : ""];
    if (error) {
        result++;
        [TUserIO eprintln: @"ERROR: Test %@ failed - %@", [self className], error];
    }
    [pool release];
    return result;
}


+ (TString *)testDataDir
{
    TString *dir = [self objectForClassKey: @"TEST_DATA_DIR"];
    if (dir == nil) {
        dir = [TFile stringByAppendingPath: [self className] to: __dataDir];
        [self setObject: dir forClassKey: @"TEST_DATA_DIR"];
        [TFile makePath: dir];
    }
    return dir;
}


- (TString *)testDataDir
{
    return [[self class] testDataDir];
}


+ (TString *)testBaseDir
{
    return __baseDir;
}


- (TString *)testBaseDir
{
    return [[self class] testBaseDir];
}


@end


int objcmain(int argc, char *argv[])
{
    int result = 0;
    if (argc < 4) {
        @throw [TTestException exceptionWithMessage: @"Need test base dir, data dir and package"];
    }
    __baseDir = [[TString stringWithCString: argv[1]] retain];
    __dataDir = [[TString stringWithCString: argv[2]] retain];
    __package = [[TString stringWithCString: argv[3]] retain];
    TString *classFilter = (argc > 4 && strlen(argv[4]) > 0) ? [TString stringWithCString: argv[4]] : nil;
    TString *methodFilter = (argc > 5 && strlen(argv[5]) > 0) ? [TString stringWithCString: argv[5]] : nil;
    TString *implementationFilter = (argc > 6 && strlen(argv[6]) > 0) ? [TString stringWithCString: argv[6]] : nil;
    if ([classFilter hasSuffix: @"Test"]) {
        classFilter = [classFilter substringToIndex: [classFilter length] - 4];
    }

    TMutableDictionary *testClasses = [TMutableDictionary dictionary];
    Class testCaseClass = [TTestCase class];
    int classCount = objc_getClassList(NULL, 0);
    Class *classes = alloca(classCount * sizeof(Class));
    objc_getClassList(classes, classCount);
    for (int i = 0; i < classCount; i++) {
        Class class = classes[i];
        // GCC-Bug http://gcc.gnu.org/bugzilla/show_bug.cgi?id=51892
        [class class];
        if (class_respondsToSelector(object_getClass(class), @selector(isKindOf:)) &&
                [class isKindOf: testCaseClass] && ![[class className] matches: @"TestCase$"] &&
                (classFilter == nil || [[class className] matches: classFilter])) {
            [testClasses setObject: class forKey: [class className]];
        }
    }
    for (id <TIterator> i = [[[testClasses allKeys] sortedArrayUsing:
            @selector(caseInsensitiveCompare:)] iterator]; [i hasCurrent]; [i next]) {
        Class testClass = [testClasses objectForKey: [i current]];
        if ([testClass conformsTo: @protocol(ProtocolTester)]) {
            for (int i = 0; i < classCount; i++) {
                Class class = classes[i];
                // GCC's “conformsTo:” is broken
                if (class_respondsToSelector(object_getClass(class), @selector(isKindOf:)) &&
                        [class isKindOf: [TObject class]] &&
                        [class conformsTo: [testClass protocolUnderTest]] &&
                        (implementationFilter == nil || [[class className] matches: implementationFilter])) {
                    TTestCase *test = nil;
                    @try {
                        SEL initializer = [TUtils selectorFromString:
                                [TString stringWithFormat: @"initFor%@", [class className]]];
                        test = [testClass alloc];
                        if ([test respondsTo: initializer]) {
                            [test perform: initializer];
                        } else {
                            [test perform: [TUtils selectorFromString: @"initFor:"] with: class];
                        }
                        result += [test run: methodFilter for: class];
                    } @finally {
                        [test release];
                    }
                }
            }
        } else {
            TTestCase *test = nil;
            @try {
                test = [[testClass alloc] init];
                result += [test run: methodFilter for: Nil];
            } @finally {
                [test release];
            }
        }
    }
    return result;
}
