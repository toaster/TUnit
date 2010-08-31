//
// (C) Copyright Tilo Prütz
//

#include "TTestCaseTest.h"

#pragma .h #include <TUnit/TUnit.h>


@implementation TTestCaseTest:TTestCase
{
}


- (void)testAssertListsContentsEqualDoesNotFailOnListsWithEqualElements
{
    ASSERTLISTCONTENTSEQUAL(A(@"a", I(123), @"z"), A(@"z", @"a", I(123)));
}


- (void)testAssertListsContentsEqualDoesFailsIfListsContentsDiffer
{
    FAIL(ASSERTLISTCONTENTSEQUAL(A(@"a", I(123)), A(@"z", @"a", I(123))));
    FAIL(ASSERTLISTCONTENTSEQUAL(A(@"a", I(123), @"z"), A(@"z", @"a")));
}


@end

