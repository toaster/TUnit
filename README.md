TUnit
=====

A unit test framework for Objective-C.


What for? – History
-------------------

Inspired by TDD talks on JAOO 2003 I found that I am lacking an Objective-C unit test framework.

Searching the net I found OCUnit and some other I forgot about. Both were either bound to Apples
Cocoa Framework or did not behave like I expected. So I decided to write my own one on top of my own
little Foundation (TFoundation - not public as of September 2010).

Later I missed mock objects and build them in inspired by EasyMock.

Then I found more inspiration when testing Ruby code with RSpec and I added a better mocking
framework based on dynamic modification of objects and classes.


Requirements
------------

TUnit actually requires the non public TFoundation. Nevertheless it would run with any other
“Foundation” if one implements a tiny wrapper layer (which I actually have done for the very old
libFoundation and which should be easy to transfer to Cocoa or GNUStep).

TUnit requires the usage of “-fobjc-exceptions” (@try/@catch…).

TUnit was build with and for the GNU runtime. It will not run on the Apple runtime without
modifications.

TUnit may not run well (or at all ;)) on non x86/x64 systems or on non linux boxes.


Why on GitHub?
--------------

So, if the stuff is so useless, why it's on GitHub?

Because its my private project which I am using in my professional environment by cloning it as a
submodule.


How to use it anyway?
---------------------

First, you could contact me via GitHub and ask for

* a public TFoundation
* support for Cocoa, GNUStep or whatever
* support for the Apple runtime
* a wrapper layer to run on Cocoa or GNUStep …
* help on compiling the stuff
* any other Objective-C/TUnit related stuff

Second, wait for my reply. I will not do any of the above without needing it for myself or someone
asking for it. And don't hesitate: One question could be enough.


How to use it when compiled and (propably) running?
---------------------------------------------------

* All test classes inherit from TTestCase.
* All test classes ending with `TestCase` will not be run.
* The instance method `-(void)setUp` is performed before every test and the instance method
`-(void)tearDown` is performed after every test.
* Every instance method beginning with `test` or `itShould` is performed as a single test.
* Assertions are made by macros (to get file and line of the assertion on failure) like ASSERT(…) or
  ASSERTEQUALS(…, …).
* A test run can be limited to classes or methods.

### Mocking

Mocking is easy as:

    id myObj = [MyClass new];
    [[[myObj shouldReceive] myMessage: someArg] andReturn: theResult];
    [myObj methodUnderTest];

If `myMessage:` is not being called with `someArg` the test will fail.

Stubbing is also available:

    [[[myObj stub] myMessage: someArg] andReturn: theResult];

Also some more tweaks are available (skip checking of some/all stubbed/mocked method parameters;
ordered messages; message call count). I will document all of it if someone performed the first step
of “How to use it anyway?”.


Any questions?
--------------

As mentioned in “How to use it anyway?”, contact me via GitHub.
