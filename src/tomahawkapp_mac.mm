#include "tomahawkapp_mac.h"
#include "tomahawkapp_macdelegate.h"
#include <QDebug>

#import <AppKit/NSApplication.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSError.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSAppleEventManager.h>
#import <Foundation/NSURL.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSNibDeclarations.h>

// Capture global media keys on Mac (Cocoa only!)
// See: http://www.rogueamoeba.com/utm/2007/09/29/apple-keyboard-media-key-event-handling/

@interface MacApplication :NSApplication {
 // MacGlobalShortcutBackend* shortcut_handler_;
    Tomahawk::PlatformInterface* application_handler_;
}

//- (MacGlobalShortcutBackend*) shortcut_handler;
//- (void) SetShortcutHandler: (MacGlobalShortcutBackend*)handler;

- (Tomahawk::PlatformInterface*) application_handler;
- (void) SetApplicationHandler: (Tomahawk::PlatformInterface*)handler;
- (void)getUrl:(NSAppleEventDescriptor *)event  withReplyEvent:(NSAppleEventDescriptor *)replyEvent;
//- (void) mediaKeyEvent: (int)key state: (BOOL)state repeat: (BOOL)repeat;
@end


@implementation AppDelegate

- (id) init {
  if ((self = [super init])) {
    application_handler_ = nil;
//    dock_menu_ = nil;
  }
  return self;
}

- (id) initWithHandler: (Tomahawk::PlatformInterface*)handler {
  application_handler_ = handler;
  return self;
}

- (BOOL) applicationShouldHandleReopen: (NSApplication*)app hasVisibleWindows:(BOOL)flag {
  if (application_handler_) {
    application_handler_->activate();
  }
  return YES;
}
/*
- (void) setDockMenu: (NSMenu*)menu {
  dock_menu_ = menu;
}

- (NSMenu*) applicationDockMenu: (NSApplication*)sender {
  return dock_menu_;
}
*/
- (BOOL) application: (NSApplication*)app openFile:(NSString*)filename {
  qDebug() << "Wants to open:" << [filename UTF8String];

  if (application_handler_->loadUrl(QString::fromUtf8([filename UTF8String]))) {
    return YES;
  }

  return NO;
}
@end

@implementation MacApplication

- (id) init {
  if ((self = [super init])) {
//    [self SetShortcutHandler:nil];
      [self SetApplicationHandler:nil];

      NSAppleEventManager *em = [NSAppleEventManager sharedAppleEventManager];
      [em
        setEventHandler:self
        andSelector:@selector(getUrl:withReplyEvent:)
        forEventClass:kInternetEventClass
        andEventID:kAEGetURL];
      [em
        setEventHandler:self
        andSelector:@selector(getUrl:withReplyEvent:)
        forEventClass:'WWW!'
        andEventID:'OURL'];
      NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
      OSStatus httpResult = LSSetDefaultHandlerForURLScheme((CFStringRef)@"tomahawk", (CFStringRef)bundleID);
      //TODO: Check httpResult and httpsResult for errors
  }
  return self;
}
/*
- (MacGlobalShortcutBackend*) shortcut_handler {
  return shortcut_handler_;
}

- (void) SetShortcutHandler: (MacGlobalShortcutBackend*)handler {
  shortcut_handler_ = handler;
}
*/
- (Tomahawk::PlatformInterface*) application_handler {
  return application_handler_;
}

- (void) SetApplicationHandler: (Tomahawk::PlatformInterface*)handler {
  AppDelegate* delegate = [[AppDelegate alloc] initWithHandler:handler];
  [self setDelegate:delegate];
}

-(void) sendEvent: (NSEvent*)event {
  if ([event type] == NSSystemDefined && [event subtype] == 8) {
    int keycode = (([event data1] & 0xFFFF0000) >> 16);
    int keyflags = ([event data1] & 0x0000FFFF);
    int keystate = (((keyflags & 0xFF00) >> 8)) == 0xA;
    int keyrepeat = (keyflags & 0x1);

    //[self mediaKeyEvent: keycode state: keystate repeat: keyrepeat];
  }

  [super sendEvent: event];
}
/*
-(void) mediaKeyEvent: (int)key state: (BOOL)state repeat: (BOOL)repeat {
  if (!shortcut_handler_) {
    return;
  }
  if (state == 0) {
    shortcut_handler_->MacMediaKeyPressed(key);
  }
} */

- (void)getUrl:(NSAppleEventDescriptor *)event
    withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
  // Get the URL
  NSString *urlStr = [[event paramDescriptorForKeyword:keyDirectObject]
    stringValue];
  qDebug() << "Wants to open:" << [urlStr UTF8String];

  //TODO: Your custom URL handling code here
}

@end

void Tomahawk::macMain() {
  [[NSAutoreleasePool alloc] init];
  // Creates and sets the magic global variable so QApplication will find it.
  [MacApplication sharedApplication];
  #ifdef HAVE_SPARKLE
    // Creates and sets the magic global variable for Sparkle.
    [[SUUpdater sharedUpdater] setDelegate: NSApp];
  #endif
}

/*
void setShortcutHandler(MacGlobalShortcutBackend* handler) {
  [NSApp SetShortcutHandler: handler];
}
*/
void Tomahawk::setApplicationHandler(Tomahawk::PlatformInterface* handler) {
  [NSApp SetApplicationHandler: handler];
}

void CheckForUpdates() {
  #ifdef HAVE_SPARKLE
  [[SUUpdater sharedUpdater] checkForUpdates: NSApp];
  #endif
}

QString GetBundlePath() {
  CFURLRef app_url = CFBundleCopyBundleURL(CFBundleGetMainBundle());
  CFStringRef mac_path = CFURLCopyFileSystemPath(app_url, kCFURLPOSIXPathStyle);
  const char* path = CFStringGetCStringPtr(mac_path, CFStringGetSystemEncoding());
  QString bundle_path = QString::fromUtf8(path);
  CFRelease(app_url);
  CFRelease(mac_path);
  return bundle_path;
}

QString GetResourcesPath() {
  QString bundle_path = GetBundlePath();
  return bundle_path + "/Contents/Resources";
}

QString GetApplicationSupportPath() {
  NSAutoreleasePool* pool = [NSAutoreleasePool alloc];
  [pool init];
  NSArray* paths = NSSearchPathForDirectoriesInDomains(
      NSApplicationSupportDirectory,
      NSUserDomainMask,
      YES);
  QString ret;
  if ([paths count] > 0) {
    NSString* user_path = [paths objectAtIndex:0];
    ret = QString::fromUtf8([user_path UTF8String]);
  } else {
    ret = "~/Library/Application Support";
  }
  [pool drain];
  return ret;
}

QString GetMusicDirectory() {
  NSAutoreleasePool* pool = [NSAutoreleasePool alloc];
  [pool init];
  NSArray* paths = NSSearchPathForDirectoriesInDomains(
      NSMusicDirectory,
      NSUserDomainMask,
      YES);
  QString ret;
  if ([paths count] > 0) {
    NSString* user_path = [paths objectAtIndex:0];
    ret = QString::fromUtf8([user_path UTF8String]);
  } else {
    ret = "~/Music";
  }
  [pool drain];
  return ret;
}

