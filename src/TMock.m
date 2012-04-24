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
            protocol_getMethodDescription(self->_protocol, sel, YES, YES).name == NULL) ||
            (self->_metaClass != NULL &&
            ![(Class)self->_metaClass instancesRespondTo: sel]) ||
            (self->_metaClass == NULL && self->_class != Nil &&
            ![self->_class instancesRespondTo: sel])) {
        @throw [TTestException exceptionWithFormat:
                @"%@ received invalid message '%@'",
                [TMockController descriptionFor: self],
                [TUtils stringFromSelector: sel]];
    }
}


- (TMethodSignature *)methodSignatureForSelector: (SEL)sel
{
    const char *types = sel_getTypeEncoding(sel);
    if (!types) {
        Method m = class_isMetaClass(object_getClass(self)) ?
                class_getClassMethod((Class)self, sel) :
                class_getInstanceMethod(self->_isa, sel);
        types = method_getTypeEncoding(m);
    }
    TMethodSignature *sig = nil;
    if (types) {
        sig = [TMethodSignature signatureWithObjCTypes: types];
    }
    return sig;
}


- (void)forward: (TInvocation *)invocation
{
    checkForResponsibility(self, [invocation selector]);
    [_controller mock: self gotInvocation: invocation];
}


- autorelease
{
    [TAutoreleasePool autorelease: self];
    return self;
}


@end
