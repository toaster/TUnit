//
// (C) Copyright Tilo Prütz
//

#include "TUnit/TMock.h"

#pragma .h #include <TFoundation/TFoundation.h>

#pragma .h #include "TUnit/TMockController.h"

#include <objc/runtime.h>

#include "TUnit/TTestException.h"


@implementation __TMock__
{
@public
    Class _isa;
}


+ (void)initialize
{
}


@end


@implementation TMock:__TMock__
{
@public
    TMockController *_controller;
    Class _class;
    MetaClass _metaClass;
    Protocol *_protocol;
    TMockList *_mockListEntry;
    TString *_name;
}


+ (Class)class
{
    return self;
}


static inline void checkForResponsibility(TMock *self, SEL sel)
{
    if ((self->_protocol != nil &&
            ![self->_protocol instancesRespondTo: sel]) ||
            (self->_metaClass != Nil &&
            ![self->_metaClass instancesRespondTo: sel]) ||
            (self->_metaClass == nil && self->_class != Nil &&
            ![self->_class instancesRespondTo: sel])) {
        @throw [TTestException exceptionWithFormat:
                @"%@ received invalid message '%@'",
                [TMockController descriptionFor: self],
                [TUtils stringFromSelector: sel]];
    }
}


- (byte)byteForward: (SEL)sel : (arglist_t)argFrame
{
    checkForResponsibility(self, sel);
    return [_controller mock: self gotByteMsg: (SEL)sel withArgFrame: argFrame];
}


- (word)wordForward: (SEL)sel : (arglist_t)argFrame
{
    checkForResponsibility(self, sel);
    return [_controller mock: self gotWordMsg: (SEL)sel withArgFrame: argFrame];
}


- (dword)dwordForward: (SEL)sel : (arglist_t)argFrame
{
    checkForResponsibility(self, sel);
    return [_controller mock: self gotDwordMsg: (SEL)sel
            withArgFrame: argFrame];
}


- (qword)qwordForward: (SEL)sel : (arglist_t)argFrame
{
    checkForResponsibility(self, sel);
    return [_controller mock: self gotQwordMsg: (SEL)sel
            withArgFrame: argFrame];
}


- (float)floatForward: (SEL)sel : (arglist_t)argFrame
{
    checkForResponsibility(self, sel);
    return [_controller mock: self gotFloatMsg: (SEL)sel
            withArgFrame: argFrame];
}


- (double)doubleForward: (SEL)sel : (arglist_t)argFrame
{
    checkForResponsibility(self, sel);
    return [_controller mock: self gotDoubleMsg: (SEL)sel
            withArgFrame: argFrame];
}


- (void)voidForward: (SEL)sel : (arglist_t)argFrame
{
    checkForResponsibility(self, sel);
    [_controller mock: self gotVoidMsg: (SEL)sel withArgFrame: argFrame];
}


- (block)blockForward: (SEL)sel : (arglist_t)argFrame
{
    @throw [TTestException exceptionWithFormat: @"Methods that return blocks "
            @"(struct, union, array) are not mockable."];
    return (block)0;
}


- autorelease
{
    [TAutoreleasePool autorelease: self];
    return self;
}


@end
