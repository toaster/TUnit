//
// (C) Copyright Tilo Prütz
//

#include "TUnit/TTestCase.h"

#pragma .h #include <TFoundation/TFoundation.h>

#pragma .h @class TString;

#include <objc/objc.h>
#include <objc/objc-api.h>

#include "TUnit/TTestException.h"
#include "TUnit/TMockController.h"
#include "TUnit/TMockMessage.h"
#include "TUnit/TObject.Mock.h"


#pragma .h #define ASSERTEQUALSINT(int1, int2) [self _assertInt: int1 equalsInt: int2\
#pragma .h         file: __FILE__ line: __LINE__]

#pragma .h #define ASSERTISGREATERTHANINT(int1, int2) [self _assertInt: int1 isGreaterThan: int2\
#pragma .h         file: __FILE__ line: __LINE__]

#pragma .h #define ASSERTISLESSTHANINT(int1, int2) [self _assertInt: int1 isLessThan: int2\
#pragma .h         file: __FILE__ line: __LINE__]

#pragma .h #define ASSERTEQUALS(obj1, obj2) [self _assert: obj1 equals: obj2\
#pragma .h         file: __FILE__ line: __LINE__]

#pragma .h #define ASSERTIDENTICAL(obj1, obj2) [self _assert: obj1 isIdenticalTo: obj2\
#pragma .h         file: __FILE__ line: __LINE__]

#pragma .h #define ASSERT(x) [self _assert: @#x isTrue: x shouldBeFalse: NO\
#pragma .h         file: __FILE__ line: __LINE__]

#pragma .h #define ASSERTFALSE(x) [self _assert: @#x isTrue: x shouldBeFalse: YES\
#pragma .h         file: __FILE__ line: __LINE__]

#pragma .h #define ASSERTKINDOF(expectedClass, obj) [self _assert: obj isKindOf: expectedClass\
#pragma .h         file: __FILE__ line: __LINE__]

#pragma .h #define ASSERTLISTCONTENTSEQUAL(expected, got) [self _assertList: got\
#pragma .h         containsEqualElementsAs: expected file: __FILE__ line: __LINE__]

#pragma .h #define ASSERTSUBSTRING(expected, got) [self _assert: got hasSubstring: expected\
#pragma .h         file: __FILE__ line: __LINE__]

// FIXME Zeitmessung bauen
/*#pragma .h #define ASSERTISFASTERTHAN(fast, slow, howMany) {\
/#pragma .h     long long __fastTime__ = [OSTime currentTimeMillis];\
/#pragma .h \
/#pragma .h     for (int __i__ = 0; __i__ < howMany; ++__i__) {\
/#pragma .h         fast;\
/#pragma .h     }\
/#pragma .h     __fastTime__ = [OSTime currentTimeMillis] - __fastTime__;\
/#pragma .h \
/#pragma .h     long long __slowTime__ = [OSTime currentTimeMillis];\
/#pragma .h \
/#pragma .h     for (int __i__ = 0; __i__ < howMany; ++__i__) {\
/#pragma .h         slow;\
/#pragma .h     }\
/#pragma .h     __slowTime__ = [OSTime currentTimeMillis] - __slowTime__;\
/#pragma .h     ASSERTISLESSTHANINT(__fastTime__, __slowTime__);\
/#pragma .h }*/


#pragma .h #define FAIL(x) {\
#pragma .h     BOOL failed = NO;\
#pragma .h \
#pragma .h     @try {\
#pragma .h         x;\
#pragma .h     } @catch(id e) {\
#pragma .h         failed = YES;\
#pragma .h     }\
#pragma .h     if (!failed) {\
#pragma .h         @throw [TTestException exceptionAt: __FILE__ : __LINE__ \
#pragma .h                 withMessage: @"Assertion " @#x @" did not fail"];\
#pragma .h     }\
#pragma .h }


@implementation TTestCase:TObject
{
}


- (void)_assert: obj1 equals: obj2 file: (const char *)file line: (int)line
{
    if ((obj1 != nil || obj2 != nil) && ![obj1 isEqual: obj2]) {
        TString *msg = nil;
        if ([obj1 isKindOf: [TDictionary class]] && [obj2 isKindOf: [TDictionary class]]) {
            msg = [self _dictDiff: obj1 : obj2];
        }
        @throw [TTestException exceptionAt: file : line
                withFormat: @"Assertion failed: %@ is not equal %@%s%@",
                obj1, obj2, msg != nil ? ":\n" : "", msg];
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
    return object_get_class(obj) == [TMock class] ? (id)[TMockController descriptionFor: obj] : obj;
}


- (void)_assertInt: (int)int1 equalsInt: (int)int2 file: (const char *)file line: (int)line
{
    if (int1 != int2) {
        @throw [TTestException exceptionAt: file : line withFormat: 
                @"Assertion failed: %d is not equal %d", int1, int2];
    }
}


- (void)_assertInt: (int)int1 isGreaterThan: (int)int2
        file: (const char *)file line: (int)line
{
    if (int1 <= int2) {
        @throw [TTestException exceptionAt: file : line withFormat:
                @"%d is not greater than %d", int1, int2];
    }
}


- (void)_assertInt: (int)int1 isLessThan: (int)int2
        file: (const char *)file line: (int)line
{
    if (int1 >= int2) {
        @throw [TTestException exceptionAt: file : line withFormat:
                @"%d is not less than %d", int1, int2];
    }
}


- (void)_assert: obj1 isIdenticalTo: obj2
        file: (const char *)file line: (int)line
{
    if (obj1 != obj2) {
        @throw [TTestException exceptionAt: file : line withFormat: 
                @"Assertion failed: %@(%p) is not identical to %@(%p)",
                obj1, obj1, obj2, obj2];
    }
}


- (void)_assert: (TString *)expression isTrue: (BOOL)isTrue
        shouldBeFalse: (BOOL)shouldBeFalse file: (const char *)file
        line: (int)line
{
    if ((!isTrue && !shouldBeFalse) || (isTrue && shouldBeFalse)) {
        @throw [TTestException exceptionAt: file : line
                withFormat: @"Assertion failed: %@ is not %s", expression,
                shouldBeFalse ? "false" : "true"];
    }
}


- (void)_assert: obj isKindOf: (Class)expectedClass
        file: (const char *)file line: (int)line
{
    if (![obj isKindOf: expectedClass]) {
        @throw [TTestException exceptionAt: file : line withFormat:
                @"object's class %@ is not kind of expected class %@",
                [obj className], [expectedClass className]];
    }
}


- (void)_assertList: (TArray *)got containsEqualElementsAs: (TArray *)expected
        file: (const char *)file line: (int)line
{
    id unexpected = [TMutableArray array];
    for (id <TIterator> i = [got iterator]; [i hasCurrent]; [i next]) {
        if (![expected containsObject: [i current]]) {
            [unexpected addObject: [i current]];
        }
    }
    id missed = [TMutableArray array];
    for (id <TIterator> i = [expected iterator]; [i hasCurrent]; [i next]) {
        if (![got containsObject: [i current]]) {
            [missed addObject: [i current]];
        }
    }
    if ([unexpected count] > 0 || [missed count] > 0) {
        @throw [TTestException exceptionAt: file : line withFormat: @"Assertion failed: "
                @"%@ does not contain the same elements as the expected list %@:%s%@%s%@",
                got, expected,
                [unexpected count] > 0 ? "\nUnexpected: " : "",
                [unexpected count] > 0 ? unexpected : nil,
                [missed count] > 0 ? "\nMissed: " : "",
                [missed count] > 0 ? missed : nil];
    }
}


- (void)_assert: obj hasSubstring: (TString *)string file: (const char *)file line: (int)line
{
    if (obj == nil || string == nil ||
            strstr([[obj stringValue] cString], [string cString]) == NULL) {
        @throw [TTestException exceptionAt: file : line
                withFormat: @"Assertion failed: %@ does not have the substring %@", obj, string];
    }
}


- (void)prepare
{
}


- (void)cleanup
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


- (int)run
{
    int result = 0;
    TAutoreleasePool *pool = [[TAutoreleasePool alloc] init];
    struct objc_method_list *list = [self class]->methods;

    while (list != NULL) {
        int i;

        for (i = 0; list->method_count > i; ++i) {
            SEL sel = list->method_list[i].method_name;
            TString *method = [TUtils stringFromSelector: sel];

            if ([method hasPrefix: @"test"]) {
                [TUserIO println: @"  Running %@ ...", method];
                TStack *exceptions = [TStack stack];
                @try {
                    [TMockMessage cleanupOrderedMessages];
                    [self prepare];
                    @try {
                        [self perform: sel];
                    } @catch(id e) {
                        [exceptions push: e];
                    } @finally {
                        @try {
                            verifyAndCleanupMocks();
                        } @catch(id e) {
                            [exceptions push: e];
                        } @finally {
                            [self cleanup];
                        }
                    }
                } @catch(id e) {
                    [exceptions push: e];
                }
                if ([exceptions containsData]) {
                    ++result;
                    [TUserIO eprintln: @"error: Test %@:%@ failed - %@",
                            [self className], method, [exceptions pop]];
                    while ([exceptions containsData]) {
                        [TUserIO eprintln: @"Root cause:\n%@", [exceptions pop]];
                    }
                }
            }
        }
        list = list->method_next;
    }
    [pool release];
    return result;
}


@end


int objcmain(int argc, char *argv[])
{
    int result = 0;
    void *classIterator = NULL;
    Class class;
    Class testCaseClass = [TTestCase class];
    TString *expectedClass = nil;
    if (argc == 2) {
        expectedClass = [TString stringWithCString: argv[1]];
    }

    while ((class = objc_next_class(&classIterator)) != Nil) {
        [class initialize];
        if (class_get_class_method(class->class_pointer,
                @selector(isKindOf:)) && class != testCaseClass &&
                [class isKindOf: testCaseClass] &&
                (expectedClass == nil || [expectedClass isEqual: [class className]])) {
            TTestCase *test = [[class alloc] init];

            [TUserIO println: @"Testing %@ ...", [class className]];
            result += [test run];
            [TUserIO println: @"Finished %@", [class className]];
            [test release];
        }
    }
    return result;
}
