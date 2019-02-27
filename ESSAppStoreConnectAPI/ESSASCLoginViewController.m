//
//  ESSASCLoginViewController.m
//  PromoCodes
//
//  Created by Matthias Gansrigler on 13.02.2019.
//  Copyright © 2019 Eternal Storms Software. All rights reserved.
//

#import "ESSASCLoginViewController.h"
#import "ESSAppStoreConnectAPI.h"


@interface ESSASCCreateCodesViewController : NSViewController <NSTextFieldDelegate>

@property (strong) NSArray <NSDictionary *> *teams;
@property (strong) NSArray <NSDictionary *> *apps;
@property (strong) NSNumber *selectedTeamID;
@property (assign) NSUInteger currentPromoCodeQuantity;
@property (strong) NSString *currentVersion;
@property (strong) NSString *selectedAppID;
@property (strong) NSString *currentContractFilename;

@property (strong) IBOutlet NSPopUpButton *teamPopupButton;
@property (strong) IBOutlet NSPopUpButton *appPopupButton;
@property (strong) IBOutlet NSTextField *amountField;
@property (strong) IBOutlet NSButton *cancelButton;
@property (strong) IBOutlet NSButton *createButton;
@property (strong) IBOutlet NSProgressIndicator *progInd;

- (IBAction)create:(id)sender;
- (IBAction)cancel:(id)sender;

- (IBAction)selectTeam:(id)sender;
- (IBAction)selectApp:(id)sender;

@end

@interface ESSASCEnter2FACodeViewController : NSViewController <NSTextFieldDelegate>

@property (copy) NSDictionary *info;
@property (copy) NSDictionary *originalInfo;


@property (strong) IBOutlet NSTextField *codeField;
@property (strong) IBOutlet NSButton *notReceivedButton;
@property (strong) IBOutlet NSButton *resendButton;
@property (strong) IBOutlet NSButton *cancelButton;
@property (strong) IBOutlet NSButton *confirmButton;

- (IBAction)confirm:(id)sender;
- (IBAction)cancel:(id)sender;
- (IBAction)receiveAgain:(id)sender;

@end

@interface ESSASCSelect2FAPhoneViewController : NSViewController <NSTextFieldDelegate>

@property (copy) NSDictionary *info;


@property (strong) IBOutlet NSPopUpButton *numbersPopupButton;
@property (strong) IBOutlet NSButton *requestCodeButton;
@property (strong) IBOutlet NSButton *cancelButton;

- (IBAction)request:(id)sender;
- (IBAction)cancel:(id)sender;

@end

@interface ESSFinalizePromoCodesViewController : NSViewController <NSTextFieldDelegate>


@property (copy) NSArray <NSDictionary *> *createdPromoCodes;
@property (copy) NSString *createdAppName;

@end









@interface ESSASCLoginViewController ()

@property (strong) IBOutlet NSTextField *usernameField;
@property (strong) IBOutlet NSTextField *passwordField;
@property (strong) IBOutlet NSButton *cancelButton;
@property (strong) IBOutlet NSButton *loginButton;
@property (strong) IBOutlet NSProgressIndicator *progInd;

- (IBAction)login:(id)sender;
- (IBAction)cancel:(id)sender;

@end

@implementation ESSASCLoginViewController

- (void)viewDidLoad
{
	[super viewDidLoad];
	// Do view setup here.
	
	self.usernameField.delegate = self.passwordField.delegate = self;
}

- (void)viewDidAppear
{
	[super viewDidAppear];
	
	[self.view.window setInitialFirstResponder:self.usernameField];
	
	[self disableInterfaceForLogin];
	
	[[ESSAppStoreConnectAPI sharedAPI] checkLoginWithCompletionHandler:^(BOOL loggedIn, NSArray<NSDictionary *> *teams, NSNumber *currentTeamID, NSArray<NSDictionary *> *apps, NSError *error) {
		if (!loggedIn || error != nil)
		{
			[self enableInterfaceAfterLogin];
			return;
		}
		
		//we're already logged in, proceed to create promocode view
		[self performSegueWithIdentifier:@"createPromoCodes" sender:@[teams,currentTeamID,apps]];
	}];
}

- (void)disableInterfaceForLogin
{
	self.usernameField.enabled = self.passwordField.enabled = self.cancelButton.enabled = self.loginButton.enabled = NO;
}

- (void)enableInterfaceAfterLogin
{
	self.usernameField.enabled = self.passwordField.enabled = self.cancelButton.enabled = self.loginButton.enabled = YES;
	
	[self enableInterfaceDependingOnLoginFields];
	
	[self.view.window makeFirstResponder:self.usernameField];
}

- (void)controlTextDidChange:(NSNotification *)obj
{
	[self enableInterfaceDependingOnLoginFields];
}

- (void)enableInterfaceDependingOnLoginFields
{
	if (self.usernameField.stringValue.length != 0 &&
		self.passwordField.stringValue.length != 0)
		self.loginButton.enabled = YES;
	else
		self.loginButton.enabled = NO;
}

- (void)login:(id)sender
{
	if (self.usernameField.stringValue.length == 0 ||
		self.passwordField.stringValue.length == 0)
	{
		NSBeep();
		return;
	}
	
	[self disableInterfaceForLogin];
	
	[[ESSAppStoreConnectAPI sharedAPI] loginWithUsername:self.usernameField.stringValue
												password:self.passwordField.stringValue
									   completionHandler:^(BOOL loggedIn, BOOL needsTwoFactorAuth, NSDictionary *info, NSError *error) {
										   if (info == nil || error != nil)
										   {
											   [self enableInterfaceAfterLogin];
											   NSBeep();
											   NSAlert *alert = [[NSAlert alloc] init];
											   alert.messageText = @"Login failed";
											   alert.informativeText = @"Logging in to App Store Connect failed.\nPlease check your username, password and internet connection.";
											   [alert addButtonWithTitle:@"OK"];
											   [alert runModal];
											   return;
										   }
										   
										   if (!loggedIn && needsTwoFactorAuth)
										   {
											   //needs to show 2fa UI
											   if ([info[@"didSendCode"] boolValue] == YES)
											   {
												   //show enter code ui
												   [self performSegueWithIdentifier:@"2faCode" sender:info];
											   } else
											   {
												   //show select phone ui
												   [self performSegueWithIdentifier:@"2faSelect" sender:info];
											   }
											   return;
										   }
										   
										   NSArray *teams = info[@"teams"];
										   NSNumber *teamID = info[@"teamID"];
										   NSArray *apps = info[@"apps"];
										   
										   [self performSegueWithIdentifier:@"createPromoCodes" sender:@[teams,teamID,apps]];
									   }];
}

- (void)cancel:(id)sender
{
	[self dismissController:sender];
}

- (void)prepareForSegue:(NSStoryboardSegue *)segue sender:(id)sender
{
	if ([segue.identifier isEqualToString:@"createPromoCodes"])
	{
		ESSASCCreateCodesViewController *ctr = (ESSASCCreateCodesViewController *)segue.destinationController;
		NSArray *res = (NSArray *)sender;
		ctr.teams = res[0];
		ctr.selectedTeamID = res[1];
		ctr.apps = res[2];
	} else if ([segue.identifier isEqualToString:@"2faSelect"])
	{
		ESSASCSelect2FAPhoneViewController *ctr = (ESSASCSelect2FAPhoneViewController *)segue.destinationController;
		ctr.info = sender;
	} else if ([segue.identifier isEqualToString:@"2faCode"])
	{
		ESSASCEnter2FACodeViewController *ctr = (ESSASCEnter2FACodeViewController *)segue.destinationController;
		ctr.info = sender;
	}
}

@end







@implementation ESSASCCreateCodesViewController

- (void)viewWillAppear
{
	[super viewWillAppear];
	
	self.amountField.delegate = self;
	[self setup];
}

- (void)viewDidAppear
{
	[super viewDidAppear];
	
	[self.view.window setInitialFirstResponder:self.teamPopupButton];
	[self.view.window makeFirstResponder:self.teamPopupButton];
}

- (void)controlTextDidChange:(NSNotification *)obj
{
	NSCharacterSet *unallowedSet = [NSCharacterSet characterSetWithCharactersInString:@"1234567890"].invertedSet;
	
	NSString *str = self.amountField.stringValue;
	
	NSRange range = [str rangeOfCharacterFromSet:unallowedSet];
	while (range.location != NSNotFound)
	{
		str = [str stringByReplacingCharactersInRange:range withString:@""];
		range = [str rangeOfCharacterFromSet:unallowedSet];
	}
	
	self.amountField.stringValue = str;
	
	if (str.integerValue > self.currentPromoCodeQuantity)
		self.amountField.stringValue = [NSString stringWithFormat:@"%ld",self.currentPromoCodeQuantity];
	
	self.createButton.enabled = (self.amountField.stringValue.length > 0 && self.amountField.stringValue.integerValue > 0);
}

- (void)setup
{
	[self.teamPopupButton removeAllItems];
	
	for (NSDictionary *dict in self.teams)
	{
		NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:dict[@"name"] action:@selector(selectTeam:) keyEquivalent:@""];
		it.representedObject = dict;
		[self.teamPopupButton.menu addItem:it];
		
		if ([dict[@"providerID"] isEqualToNumber:self.selectedTeamID])
			[self.teamPopupButton selectItem:it];
	}
	
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	for (NSDictionary *aDict in self.apps)
	{
		NSArray *arr = dict[aDict[@"platform"]];
		if (arr == nil)
			arr = [NSArray array];
		arr = [arr arrayByAddingObject:aDict];
		dict[aDict[@"platform"]] = arr;
	}
	
	NSArray *macApps = dict[@"osx"];
	NSArray *iosApps = dict[@"ios"];
	NSArray *tvApps = dict[@"appletvos"];
	
	[self.appPopupButton removeAllItems];
	if (macApps.count == 0 && iosApps.count == 0 && tvApps.count == 0)
	{
		self.appPopupButton.enabled = NO;
		self.appPopupButton.title = @"No apps available in this team";
	} else
	{
		self.appPopupButton.enabled = YES;
		self.appPopupButton.title = @"";
		[self.appPopupButton removeAllItems];
		
		self.appPopupButton.menu.autoenablesItems = NO;
		self.appPopupButton.autoenablesItems = NO;
		
		if (macApps.count != 0)
		{
			NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:@"macOS" action:nil keyEquivalent:@""];
			it.enabled = NO;
			it.target = nil;
			it.action = nil;
			
			[self.appPopupButton.menu addItem:it];
			
			for (NSDictionary *dict in macApps)
			{
				it = [[NSMenuItem alloc] initWithTitle:dict[@"name"] action:@selector(selectApp:) keyEquivalent:@""];
				it.representedObject = dict;
				it.toolTip = dict[@"bundleID"];
				it.indentationLevel = 1;
				it.enabled = YES;
				[self.appPopupButton.menu addItem:it];
			}
		}
		
		if (iosApps.count != 0)
		{
			NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:@"iOS" action:nil keyEquivalent:@""];
			it.enabled = NO;
			it.target = nil;
			it.action = nil;
			[self.appPopupButton.menu addItem:it];
			
			for (NSDictionary *dict in iosApps)
			{
				it = [[NSMenuItem alloc] initWithTitle:dict[@"name"] action:@selector(selectApp:) keyEquivalent:@""];
				it.representedObject = dict;
				it.toolTip = dict[@"bundleID"];
				it.indentationLevel = 1;
				it.enabled = YES;
				[self.appPopupButton.menu addItem:it];
			}
		}
		
		if (tvApps.count != 0)
		{
			NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:@"tvOS" action:nil keyEquivalent:@""];
			it.enabled = NO;
			it.target = nil;
			it.action = nil;
			[self.appPopupButton.menu addItem:it];
			
			for (NSDictionary *dict in tvApps)
			{
				it = [[NSMenuItem alloc] initWithTitle:dict[@"name"] action:@selector(selectApp:) keyEquivalent:@""];
				it.representedObject = dict;
				it.toolTip = dict[@"bundleID"];
				it.indentationLevel = 1;
				it.enabled = YES;
				[self.appPopupButton.menu addItem:it];
			}
		}
		
		[self.appPopupButton selectItem:nil];
	}
	
	self.amountField.enabled = NO;
	self.amountField.placeholderString = @"";
}

- (void)disableInterfaceWhileLoading
{
	self.teamPopupButton.enabled = self.appPopupButton.enabled = self.cancelButton.enabled = self.createButton.enabled = self.amountField.enabled = NO;
	self.createButton.hidden = YES;
	self.progInd.hidden = NO;
	[self.progInd startAnimation:nil];
}

- (void)enableInterfaceAfterLoading
{
	self.teamPopupButton.enabled = self.appPopupButton.enabled = self.cancelButton.enabled = self.createButton.enabled = self.amountField.enabled = YES;
	self.createButton.hidden = NO;
	self.progInd.hidden = YES;
	[self.progInd stopAnimation:nil];
	
	self.createButton.enabled = (self.amountField.stringValue.length > 0);
}

- (void)create:(id)sender
{
	if (self.amountField.stringValue.length == 0 || self.selectedAppID == nil || self.currentVersion == nil)
		return;
	
	[self disableInterfaceWhileLoading];
	
	[[ESSAppStoreConnectAPI sharedAPI] requestPromoCodesForAppWithID:self.selectedAppID
														   versionID:self.currentVersion
															quantity:self.amountField.stringValue.integerValue
													contractFileName:self.currentContractFilename
												   completionHandler:^(NSArray <NSDictionary *> *promoCodes, NSError *error) {
													   if (promoCodes == nil || error != nil)
													   {
														   [self enableInterfaceAfterLoading];
														   NSBeep();
														   return;
													   }
													   
													   [self performSegueWithIdentifier:@"finish" sender:promoCodes];
												   }];
}

- (void)cancel:(id)sender
{
	[self.view.window orderOut:nil];
}

- (void)selectTeam:(id)sender
{
	self.amountField.stringValue = @"";
	
	NSMenuItem *it = self.teamPopupButton.selectedItem;
	[self.appPopupButton selectItem:nil];
	
	NSDictionary *dict = it.representedObject;
	if (dict == nil)
		return;
	
	[self disableInterfaceWhileLoading];
	
	[[ESSAppStoreConnectAPI sharedAPI] appsForTeamWithProviderID:dict[@"providerID"]
											   completionHandler:^(NSArray *apps, NSError *error) {
												   [self enableInterfaceAfterLoading];
												   
												   if (apps == nil || error != nil)
												   {
													   NSBeep();
													   return;
												   }
												   
												   self.apps = apps;
												   self.selectedTeamID = dict[@"providerID"];
												   
												   [self setup];
											   }];
}

- (void)selectApp:(id)sender
{
	self.amountField.stringValue = @"";
	
	NSMenuItem *it = self.appPopupButton.selectedItem;
	NSDictionary *appDict = it.representedObject;
	if (appDict == nil)
		return;
	
	[self disableInterfaceWhileLoading];
	[[ESSAppStoreConnectAPI sharedAPI] promoCodeInfoForAppWithID:appDict[@"id"]
											   completionHandler:^(NSDictionary *promoCodeInfo, NSError *error) {
												   [self enableInterfaceAfterLoading];
												   
												   if (promoCodeInfo == nil || error != nil)
												   {
													   NSBeep();
													   return;
												   }
												   
												   if (promoCodeInfo.allKeys.count == 0)
												   {
													   self.amountField.placeholderString = @"no promo codes available for this app";
													   self.amountField.enabled = NO;
													   self.createButton.enabled = NO;
													   return;
												   }
												   
												   NSUInteger codesLeft = [promoCodeInfo[@"codesLeft"] integerValue];
												   NSString *version = promoCodeInfo[@"version"];
												   
												   self.currentPromoCodeQuantity = codesLeft;
												   self.currentVersion = promoCodeInfo[@"versionID"];
												   self.selectedAppID = appDict[@"id"];
												   self.currentContractFilename = promoCodeInfo[@"contractFilename"];
												   
												   if (codesLeft <= 0)
												   {
													   self.amountField.placeholderString = [NSString stringWithFormat:@"no promo codes left for version %@",version];
													   self.amountField.enabled = NO;
												   } else
												   {
													   self.amountField.placeholderString = [NSString stringWithFormat:@"%ld promo codes left for version %@",codesLeft,version];
													   self.amountField.enabled = YES;
												   }
												   self.createButton.enabled = NO; //gets enabled by typing numbers
											   }];
}

- (void)prepareForSegue:(NSStoryboardSegue *)segue sender:(id)sender
{
	if ([segue.identifier isEqualToString:@"finish"])
	{
		ESSFinalizePromoCodesViewController *ctr = (ESSFinalizePromoCodesViewController *)segue.destinationController;
		ctr.createdPromoCodes = sender;
		ctr.createdAppName = self.appPopupButton.selectedItem.title;
	}
}

@end

@implementation ESSASCEnter2FACodeViewController

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	self.originalInfo = self.info;
}

- (void)viewDidAppear
{
	[super viewDidAppear];
	
	[self.view.window makeFirstResponder:self.codeField];
	
	self.confirmButton.enabled = NO;
}

- (void)controlTextDidChange:(NSNotification *)obj
{
	self.confirmButton.enabled = (self.codeField.stringValue.length == [self.info[@"securityCode"][@"length"] integerValue]);
}

- (IBAction)confirm:(id)sender
{
	if (self.codeField.stringValue.length == 0 || self.info == nil)
	{
		NSBeep();
		return;
	}
	
	self.codeField.enabled = self.notReceivedButton.enabled = self.resendButton.enabled = self.cancelButton.enabled = self.confirmButton.enabled = NO;
	
	[[ESSAppStoreConnectAPI sharedAPI] finish2FAWithCode:self.codeField.stringValue
												 phoneID:self.info[@"resendInfo"][@"phoneID"]
									   completionHandler:^(BOOL loggedIn, NSDictionary *info, NSError *error) {
										   if (!loggedIn || info == nil || error != nil)
										   {
											   NSBeep();
											   self.codeField.enabled = self.notReceivedButton.enabled = self.resendButton.enabled = self.cancelButton.enabled = self.confirmButton.enabled = YES;
											   return;
										   }
										   
										   NSArray *teams = info[@"teams"];
										   NSNumber *teamID = info[@"teamID"];
										   NSArray *apps = info[@"apps"];
										   
										   [self performSegueWithIdentifier:@"requestCode" sender:@[teams,teamID,apps]];
									   }];
}

- (IBAction)cancel:(id)sender
{
	[self.view.window orderOut:nil];
}

- (IBAction)receiveAgain:(id)sender
{
	if ([self.info[@"phoneNumbers"] count] == 1)
	{
		//we just have one phone number, use that to send via sms.
		NSDictionary *dic = [self.info[@"phoneNumbers"] firstObject];
		NSMutableDictionary *resendDict = self.info.copy;
		resendDict[@"resendInfo"] = @{@"phoneID":dic[@"id"]};
		
		NSAlert *alert = [[NSAlert alloc] init];
		alert.messageText = @"Requesting new Code?";
		alert.informativeText = [NSString stringWithFormat:@"Do you want to request a new code via SMS sent to %@?",dic[@"numberWithDialCode"]];
		[alert addButtonWithTitle:@"Request new Code"];
		[alert addButtonWithTitle:@"Cancel"];
		if ([alert runModal] != NSAlertFirstButtonReturn)
			return;
		
		self.codeField.enabled = self.notReceivedButton.enabled = self.resendButton.enabled = self.cancelButton.enabled = self.confirmButton.enabled = NO;
		[[ESSAppStoreConnectAPI sharedAPI] resend2FACodeWithPhoneID:dic[@"id"]
												  completionHandler:^(BOOL resent, NSError *err) {
													  if (!resent || err != nil)
													  {
														  self.codeField.enabled = self.notReceivedButton.enabled = self.resendButton.enabled = self.cancelButton.enabled = self.confirmButton.enabled = YES;
														  NSBeep();
														  return;
													  }
													  
													  self.info = resendDict.copy;
												  }];
		return;
	}
	
	//have multiple phone numbers, offer selection
	
	[self performSegueWithIdentifier:@"2faResend" sender:self.info];
}

- (void)prepareForSegue:(NSStoryboardSegue *)segue sender:(id)sender
{
	if ([segue.identifier isEqualToString:@"2faResend"])
	{
		ESSASCSelect2FAPhoneViewController *ctr = (ESSASCSelect2FAPhoneViewController *)segue.destinationController;
		ctr.info = sender;
	} else if ([segue.identifier isEqualToString:@"requestCode"])
	{
		ESSASCCreateCodesViewController *ctr = (ESSASCCreateCodesViewController *)segue.destinationController;
		NSArray *res = (NSArray *)sender;
		ctr.teams = res[0];
		ctr.selectedTeamID = res[1];
		ctr.apps = res[2];
	}
}

@end

@implementation ESSASCSelect2FAPhoneViewController

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	NSArray *numbers = self.info[@"phoneNumbers"];
	[self.numbersPopupButton removeAllItems];
	for (NSDictionary *dict in numbers)
	{
		NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:dict[@"numberWithDialCode"] action:nil keyEquivalent:@""];
		it.representedObject = dict;
		[self.numbersPopupButton.menu addItem:it];
	}
	[self.numbersPopupButton selectItem:nil];
}

- (IBAction)request:(id)sender
{
	if (self.numbersPopupButton.selectedItem == nil ||
		self.numbersPopupButton.selectedItem.representedObject == nil)
	{
		NSBeep();
		return;
	}
	
	self.numbersPopupButton.enabled = self.cancelButton.enabled = self.requestCodeButton.enabled = NO;
	
	NSNumber *phoneID = [self.numbersPopupButton.selectedItem.representedObject objectForKey:@"id"];
	NSMutableDictionary *dic = self.info.mutableCopy;
	dic[@"resendInfo"] = @{@"phoneID":phoneID};
	
	[[ESSAppStoreConnectAPI sharedAPI] resend2FACodeWithPhoneID:phoneID
											  completionHandler:^(BOOL resent, NSError *err) {
												  if (!resent || err != nil)
												  {
													  self.numbersPopupButton.enabled = self.cancelButton.enabled = self.requestCodeButton.enabled = YES;
													  NSBeep();
													  return;
												  }
												  
												  [self performSegueWithIdentifier:@"2faCode" sender:dic.copy];
											  }];
}

- (void)prepareForSegue:(NSStoryboardSegue *)segue sender:(id)sender
{
	if ([segue.identifier isEqualToString:@"2faCode"])
	{
		ESSASCEnter2FACodeViewController *ctr = (ESSASCEnter2FACodeViewController *)segue.destinationController;
		ctr.info = sender;
	}
}

- (IBAction)cancel:(id)sender
{
	[self.view.window orderOut:nil];
}

@end


@interface ESSFinalizePromoCodesViewController ()

@property (strong) IBOutlet NSTextField *appNameField;
@property (strong) IBOutlet NSTextField *codesField;
@property (strong) IBOutlet NSTextField *ctField;
@property (strong) IBOutlet NSButton *allowsButton;
@property (strong) IBOutlet NSButton *cancelButton;
@property (strong) IBOutlet NSButton *createButton;
@property (strong) IBOutlet NSPopUpButton *storeButton;
@property (strong) IBOutlet NSProgressIndicator *progInd;

- (IBAction)createLinks:(id)sender;

@end

@implementation ESSFinalizePromoCodesViewController

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	self.createButton.enabled = NO;
	
	[self.view.window setInitialFirstResponder:self.appNameField];
	[self.view.window makeFirstResponder:self.appNameField];
	
	if (self.createdAppName.length != 0)
		self.appNameField.stringValue = self.createdAppName;
	if (self.createdPromoCodes.count != 0)
	{
		NSString *codeString = @"";
		NSString *platform = nil;
		for (NSDictionary *codeDict in self.createdPromoCodes)
		{
			codeString = [codeString stringByAppendingString:codeDict[@"code"]];
			if (codeDict != self.createdPromoCodes.lastObject)
				codeString = [codeString stringByAppendingString:@"\n"];
			
			if (codeString != nil)
				self.codesField.stringValue = codeString;
			
			if (platform == nil)
				platform = codeDict[@"platform"];
		}
		
		if (platform != nil)
		{
			if ([platform isEqualToString:@"osx"])
				[self.storeButton selectItemWithTag:12];
			else
				[self.storeButton selectItemWithTag:8];
		}
	}
	id obj = nil;
	[self controlTextDidChange:obj];
}

- (void)controlTextDidChange:(NSNotification *)obj
{
	self.allowsButton.enabled = (self.ctField.stringValue.length != 0);
	
	self.createButton.enabled = (self.appNameField.stringValue.length != 0 && self.codesField.stringValue.length != 0);
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
	if (control == self.codesField)
	{
		if ([NSStringFromSelector(commandSelector) isEqualToString:@"insertNewline:"] ||
			[NSStringFromSelector(commandSelector) isEqualToString:@"insertNewlineIgnoringFieldEditor:"])
		{
			[textView insertNewlineIgnoringFieldEditor:nil];
			return YES;
		}
	}
	
	return NO;
}

static NSDateFormatter *_df = nil;
- (void)createLinks:(id)sender
{
	[NSApp terminate:nil];
}

- (void)dismissController:(id)sender
{
	[self.view.window orderOut:nil];
}

@end
