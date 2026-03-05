#import <Preferences/Preferences.h>
#import <substrate.h>
#import <dlfcn.h>
#import <objc/runtime.h>

#import "prefs.h"

#define DEBUG_TAG "PreferenceLoader"
#import "debug.h"

/* {{{ Imports (Preferences.framework) */
// Weak (3.2+, dlsym)
static NSString **pPSTableCellUseEtchedAppearanceKey = NULL;
/* }}} */

/* {{{ UIDevice 3.2 Additions */
@interface UIDevice (iPad)
- (BOOL)isWildcat;
@end
/* }}} */

/* {{{ Locals */
static BOOL _Firmware_lt_60 = NO;
static BOOL _UseTopLevelFallbackDetection = NO;
static NSMutableArray *_loadedSpecifiers = nil;
static NSInteger _extraPrefsGroupSectionID = 0;
static const void *PLDidInjectKey = &PLDidInjectKey;
/* }}} */

static NSString *PLPreferenceLoaderEntriesPath(void) {
#if SIMULATOR
	return @"/opt/simject/PreferenceLoader/Preferences";
#else
	return @"/var/jb/Library/PreferenceLoader/Preferences";
#endif
}

static NSInteger PSSpecifierSort(PSSpecifier *a1, PSSpecifier *a2, void *context) {
#pragma unused(context)
	NSString *name1 = [a1 name] ?: @"";
	NSString *name2 = [a2 name] ?: @"";
	return [name1 localizedCaseInsensitiveCompare:name2];
}

static BOOL PLShouldApplyEtchedAppearance(void) {
	if(!pPSTableCellUseEtchedAppearanceKey)
		return NO;
	if(![UIDevice instancesRespondToSelector:@selector(isWildcat)])
		return NO;
	return [[UIDevice currentDevice] isWildcat];
}

static void PLApplyEtchedAppearanceToSpecifiers(NSArray *specifiers) {
	if(!PLShouldApplyEtchedAppearance())
		return;

	for(PSSpecifier *specifier in specifiers) {
		[specifier setProperty:@YES forKey:*pPSTableCellUseEtchedAppearanceKey];
	}
}

static BOOL PLLooksLikeTopLevelSettingsController(PSListController *controller) {
	// Root controllers commonly have no parent, and rootController may be self or nil.
	if([controller respondsToSelector:@selector(parentController)] &&
	   [controller respondsToSelector:@selector(rootController)]) {
		id parentController = [controller parentController];
		id rootController = [controller rootController];
		if(parentController == nil && (rootController == nil || rootController == controller))
			return YES;
	}

	// Fallback heuristic for unknown controller classes.
	if([controller respondsToSelector:@selector(specifier)] && [controller specifier] == nil) {
		NSString *className = NSStringFromClass([controller class]);
		if([className rangeOfString:@"Root" options:NSCaseInsensitiveSearch].location != NSNotFound)
			return YES;
		if([className rangeOfString:@"Settings" options:NSCaseInsensitiveSearch].location != NSNotFound)
			return YES;
		if([className rangeOfString:@"General" options:NSCaseInsensitiveSearch].location != NSNotFound)
			return YES;
	}

	return NO;
}

static NSMutableArray *PLLoadExtraSpecifiersForController(PSListController *controller) {
	NSString *basePath = PLPreferenceLoaderEntriesPath();
	NSArray *subpaths = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:basePath error:NULL];
	if(subpaths.count == 0)
		return [NSMutableArray array];

	NSMutableArray *result = [NSMutableArray array];
	for(NSString *item in subpaths) {
		if(![[item pathExtension] isEqualToString:@"plist"])
			continue;

		NSString *fullPath = [basePath stringByAppendingPathComponent:item];
		NSDictionary *plPlist = [NSDictionary dictionaryWithContentsOfFile:fullPath];
		if(!plPlist)
			continue;

		NSDictionary *topLevelFilter = [plPlist objectForKey:@"filter"] ?: [plPlist objectForKey:PLFilterKey];
		if(![PSSpecifier environmentPassesPreferenceLoaderFilter:topLevelFilter])
			continue;

		NSDictionary *entry = [plPlist objectForKey:@"entry"];
		if(!entry)
			continue;
		if(![PSSpecifier environmentPassesPreferenceLoaderFilter:[entry objectForKey:PLFilterKey]])
			continue;

		NSString *title = [[item lastPathComponent] stringByDeletingPathExtension];
		NSString *sourceBundlePath = [fullPath stringByDeletingLastPathComponent];
		NSArray *specifiers = [controller specifiersFromEntry:entry
							 sourcePreferenceLoaderBundlePath:sourceBundlePath
								 title:title];
		if(specifiers.count == 0)
			continue;

		PLApplyEtchedAppearanceToSpecifiers(specifiers);
		[result addObjectsFromArray:specifiers];
	}

	[result sortUsingFunction:(NSInteger (*)(id, id, void *))&PSSpecifierSort context:NULL];
	return result;
}

static NSInteger PLInsertionIndexForController(PSListController *controller, NSArray *specifiers) {
	NSInteger group = 0;
	NSInteger row = 0;
	if([controller getGroup:&group row:&row ofSpecifierID:_Firmware_lt_60 ? @"General" : @"TWITTER"]) {
		NSInteger index = [controller indexOfGroup:group] + [[controller specifiersInGroup:group] count];
		PLLog(@"Inserting extra specifiers at end of group %ld (index %ld)", (long)group, (long)index);
		return index;
	}

	PLLog(@"Reference group not found; inserting at end of root list");
	return [specifiers count];
}

static NSUInteger PLGroupSectionIndex(PSSpecifier *groupSpecifier, NSArray *specifiers) {
	NSUInteger groupIndex = 0;
	for(PSSpecifier *specifier in specifiers) {
		if(MSHookIvar<NSInteger>(specifier, "cellType") != PSGroupCell)
			continue;
		if(specifier == groupSpecifier)
			break;
		++groupIndex;
	}
	return groupIndex;
}

/* {{{ iPad Hooks */
%group iPad
%hook PrefsListController
- (NSString *)tableView:(UITableView *)view titleForHeaderInSection:(NSInteger)section {
	if([_loadedSpecifiers count] == 0) return %orig;
	if(section == _extraPrefsGroupSectionID) return _Firmware_lt_60 ? @"Extensions" : nil;
	return %orig;
}

- (CGFloat)tableView:(UITableView *)view heightForHeaderInSection:(NSInteger)section {
	if([_loadedSpecifiers count] == 0) return %orig;
	if(section == _extraPrefsGroupSectionID) return _Firmware_lt_60 ? 22.0f : 10.0f;
	return %orig;
}
%end
%end
/* }}} */

%hook PrefsListController
- (id)specifiers {
	id origSpecifiers = %orig;
	if(origSpecifiers == nil)
		return nil;

	if(objc_getAssociatedObject(self, PLDidInjectKey))
		return origSpecifiers;

	if(_UseTopLevelFallbackDetection && !PLLooksLikeTopLevelSettingsController(self)) {
		PLLog(@"Skipping non top-level controller: %s", class_getName([self class]));
		return origSpecifiers;
	}

	objc_setAssociatedObject(self, PLDidInjectKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	NSMutableArray *workingSpecifiers = nil;
	if([origSpecifiers isKindOfClass:[NSMutableArray class]]) {
		workingSpecifiers = (NSMutableArray *)origSpecifiers;
	} else if([origSpecifiers isKindOfClass:[NSArray class]]) {
		workingSpecifiers = [origSpecifiers mutableCopy];
	}
	if(!workingSpecifiers) {
		PLLog(@"Unexpected specifiers class: %s", class_getName([origSpecifiers class]));
		return origSpecifiers;
	}

	[_loadedSpecifiers release];
	_loadedSpecifiers = [[PLLoadExtraSpecifiersForController(self) mutableCopy] retain];
	if(_loadedSpecifiers.count == 0) {
		if(workingSpecifiers != origSpecifiers)
			return [workingSpecifiers autorelease];
		return workingSpecifiers;
	}

	PSSpecifier *groupSpecifier = [PSSpecifier groupSpecifierWithName:_Firmware_lt_60 ? @"Extensions" : nil];
	[_loadedSpecifiers insertObject:groupSpecifier atIndex:0];

	if(@available(iOS 18.0, *)) {
		NSMutableArray *copiedSpecifiers = [workingSpecifiers mutableCopy];
		if(workingSpecifiers != origSpecifiers)
			[workingSpecifiers release];
		workingSpecifiers = copiedSpecifiers;
	}

	NSInteger insertionIndex = PLInsertionIndexForController(self, workingSpecifiers);
	NSIndexSet *indices = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(insertionIndex, _loadedSpecifiers.count)];
	[workingSpecifiers insertObjects:_loadedSpecifiers atIndexes:indices];

	if(@available(iOS 18.0, *)) {
		@try {
			[self setValue:workingSpecifiers forKey:@"_specifiers"];
		} @catch (NSException *e) {
			PLLog(@"Failed to write _specifiers via KVC: %@", e);
		}
	}

	_extraPrefsGroupSectionID = (NSInteger)PLGroupSectionIndex(groupSpecifier, workingSpecifiers);
	PLLog(@"Injected %lu specifiers in %s", (unsigned long)_loadedSpecifiers.count, class_getName([self class]));

	if(workingSpecifiers != origSpecifiers)
		return [workingSpecifiers autorelease];
	return workingSpecifiers;
}
%end

%ctor {
	static const char * const kRootControllerCandidates[] = {
		"PSUISettingsRootController",
		"PSUISettingsListController",
		"PSUIRootListController",
		"PSUIPrefsListController",
		"PrefsListController",
		"PSGGeneralController",
		"PSRootController"
	};

	Class targetRootClass = Nil;
	for(size_t i = 0; i < sizeof(kRootControllerCandidates) / sizeof(kRootControllerCandidates[0]); ++i) {
		targetRootClass = objc_getClass(kRootControllerCandidates[i]);
		if(targetRootClass != Nil) {
			PLLog(@"Using root controller class %s", kRootControllerCandidates[i]);
			break;
		}
	}

	if(targetRootClass == Nil) {
		targetRootClass = objc_getClass("PSListController");
		_UseTopLevelFallbackDetection = YES;
		PLLog(@"No known root controller found; falling back to PSListController");
	}

	PLLog(@"targetRootClass = %s", targetRootClass ? class_getName(targetRootClass) : "(null)");
	%init(PrefsListController = targetRootClass);

	_Firmware_lt_60 = kCFCoreFoundationVersionNumber < 793.00;
	if(([UIDevice instancesRespondToSelector:@selector(isWildcat)] && [[UIDevice currentDevice] isWildcat]))
		%init(iPad, PrefsListController = targetRootClass);

	void *preferencesHandle = dlopen("/System/Library/PrivateFrameworks/Preferences.framework/Preferences", RTLD_LAZY | RTLD_NOLOAD);
	if(preferencesHandle) {
		pPSTableCellUseEtchedAppearanceKey = (NSString **)dlsym(preferencesHandle, "PSTableCellUseEtchedAppearanceKey");
		dlclose(preferencesHandle);
	}
}
