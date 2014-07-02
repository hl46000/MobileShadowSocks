/*
 *    ShadowSocks Per-App Proxy Plugin
 *    https://github.com/linusyang/MobileShadowSocks
 *
 *    Copyright (c) 2014 Linus Yang <laokongzi@gmail.com>
 *
 *    This program is free software: you can redistribute it and/or modify
 *    it under the terms of the GNU General Public License as published by
 *    the Free Software Foundation, either version 3 of the License, or
 *    (at your option) any later version.
 *
 *    This program is distributed in the hope that it will be useful,
 *    but WITHOUT ANY WARRANTY; without even the implied warranty of
 *    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *    GNU General Public License for more details.
 *
 *    You should have received a copy of the GNU General Public License
 *    along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#define FUNC_NAME SCDynamicStoreCopyProxies
#define ORIG_FUNC original_ ## FUNC_NAME
#define CUST_FUNC custom_ ## FUNC_NAME

#define DECL_FUNC(ret, ...) \
    extern ret FUNC_NAME(__VA_ARGS__); \
    static ret (*ORIG_FUNC)(__VA_ARGS__); \
    ret CUST_FUNC(__VA_ARGS__)

#define HOOK_FUNC() \
    MSHookFunction(FUNC_NAME, (void *) CUST_FUNC, (void **) &ORIG_FUNC)

typedef const struct __SCDynamicStore *SCDynamicStoreRef;
void MSHookFunction(void *symbol, void *replace, void **result);

static BOOL perAppEnabled = NO;
static BOOL spdyDisabled = NO;
static void LoadSettings(void)
{
    NSString *bundleName = [[NSBundle mainBundle] bundleIdentifier];
    NSDictionary *prefDict = [[NSDictionary alloc] initWithContentsOfFile:@"/var/mobile/Library/Preferences/com.linusyang.ssperapp.plist"];
    if (prefDict && bundleName) {
        NSString *prefEntry = [[NSString alloc] initWithFormat:@"Enabled-%@", bundleName];
        perAppEnabled = [[prefDict objectForKey:@"SSPerAppEnabled"] boolValue] ? [[prefDict objectForKey:prefEntry] boolValue] : NO;
        spdyDisabled = [[prefDict objectForKey:@"SSPerAppDisableSPDY"] boolValue];
        [prefEntry release];
    }
    [prefDict release];
}

DECL_FUNC(CFDictionaryRef, SCDynamicStoreRef store)
{
    if (perAppEnabled) {
        return ORIG_FUNC(store);
    }
    CFMutableDictionaryRef proxyDict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    int zero = 0;
    CFNumberRef zeroNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &zero);
    CFDictionarySetValue(proxyDict, CFSTR("HTTPEnable"), zeroNumber);
    CFDictionarySetValue(proxyDict, CFSTR("HTTPProxyType"), zeroNumber);
    CFDictionarySetValue(proxyDict, CFSTR("HTTPSEnable"), zeroNumber);
    CFDictionarySetValue(proxyDict, CFSTR("ProxyAutoConfigEnable"), zeroNumber);
    CFRelease(zeroNumber);
    return proxyDict;
}

%group TwitterHook

%hook T1SPDYConfigurationChangeListener 
- (BOOL)_shouldEnableSPDY
{
    if (spdyDisabled) {
        return NO;
    } else {
        return %orig;
    }
}
%end

%end

%group FacebookHook

%hook FBRequester
- (BOOL)allowSPDY
{
    if (spdyDisabled) {
        return NO;
    } else {
        return %orig;
    }
}

- (BOOL)useDNSCache
{
    if (spdyDisabled) {
        return NO;
    } else {
        return %orig;
    }
}
%end

%hook FBNetworkerRequest
- (BOOL)disableSPDY
{
    if (spdyDisabled) {
        return YES;
    } else {
        return %orig;
    }
}
%end

%hook FBRequesterState
- (BOOL)didUseSPDY
{
    if (spdyDisabled) {
        return NO;
    } else {
        return %orig;
    }
}
%end

%hook FBAppConfigService
- (BOOL)disableDNSCache
{
    if (spdyDisabled) {
        return YES;
    } else {
        return %orig;
    }
}
%end

%hook FBNetworker
- (BOOL)_shouldAllowUseOfDNSCache:(id)arg
{
    if (spdyDisabled) {
        return NO;
    } else {
        return %orig;
    }
}
%end

%hook FBAppSessionController
- (BOOL)networkerShouldAllowUseOfDNSCache:(id)arg
{
    if (spdyDisabled) {
        return NO;
    } else {
        return %orig;
    }
}
%end

%end

%ctor
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    LoadSettings();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)LoadSettings, CFSTR("com.linusyang.ssperapp.settingschanged"), NULL, CFNotificationSuspensionBehaviorCoalesce);
    HOOK_FUNC();

    NSString *bundleName = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleName != nil) {
        if ([bundleName isEqualToString:@"com.atebits.Tweetie2"]) {
            %init(TwitterHook);
        } else if ([bundleName isEqualToString:@"com.facebook.Facebook"]) {
            %init(FacebookHook);
        }
    }

    [pool drain];
}