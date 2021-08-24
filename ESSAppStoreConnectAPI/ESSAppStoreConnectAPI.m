//
//  ESSAppStoreConnectAPI.m
//  PromoCodes
//
//  Created by Matthias Gansrigler on 12.02.2019.
//  Copyright © 2019 Eternal Storms Software. All rights reserved.
//

#import "ESSAppStoreConnectAPI.h"

@interface ESSAppStoreConnectAPI ()

/*!
 @property		authServiceKey
 @abstract		Retrieved from App Store Connect API in @c -loginWithUsername:password:completionHandler:, this is used in every subsequent call to App Store Connect's API.
 */
@property (copy) NSString *authServiceKey;

/*!
 @property		personID
 @abstract		Identifies the currently logged in user. Needed in @c -_switchToTeamWithID:completionHandler:
 */
@property (copy) NSNumber *personID; //also dsId

/*!
 @property		currentTeamID
 @abstract		Identifies the currently selected team. Needed in @c -_appsForCurrentTeamWithCompletionHandler:
 */
@property (copy) NSNumber *currentTeamID;

/*!
 @property		currentPublicProviderID
 @abstract		Identifies the currently selected team with a public ID. Needed in @c -_appsForCurrentTeamWithCompletionHandler:
 */
@property (copy) NSNumber *currentPublicProviderID;


/*!
 @property		tfaAppleIDSessionID
 @abstract		Used during two-factor authorization, required as a header value
 */
@property (copy) NSString *tfaAppleIDSessionID;

/*!
 @property		tfaScnt
 @abstract		Used during two-factor authorization, required as a header value
 */
@property (copy) NSString *tfaScnt;


/*!
 @property		cachedTeams
 @abstract		The teams available to the user. Cached after login is complete and @c -_loadSessionDataAfterLoginWithCompletionHandler is called.
 */
@property (copy) NSArray <NSDictionary *> *cachedTeams;

/*!
 @property		cachedAppsKeyedByTeamID;
 @abstract		The apps available in a team, keyed by a team's ID. Used in @c -appsForTeamWithProvider:completionHandler: as to not call the server all the time when switching teams.
 */
@property (strong) NSMutableDictionary <NSString *, NSArray <NSDictionary *> *> *cachedAppsKeyedByTeamID;

/*!
 @method		isLoggedIn
 @abstract		Returns YES if @c authServiceKey and @c personID are both set.
 */
- (BOOL)isLoggedIn;

/*!
 @method		_updateHeadersForRequest:additionalFields:
 @abstract		Sets the appropriate headers for the supplied request. Additional fields can be supplied using @c additionalFields.
 @param			req The request to set header fields for. If nil, nothing happens.
 @param			additionalFields Optional additional header fields.
 */
- (void)_updateHeadersForRequest:(NSMutableURLRequest *)req additionalFields:(NSDictionary *)additionalFields;

/*!
 @method		_loadSessionDataAfterLoginWithCompletionHandler:
 @abstract		Call to load the session's data. Contains all teams (availableProviders) and their contentProviderIds, the currently selected team (provider) and info about the current user (user). This also calls @c -appsForTeamWithProviderID:completionHandler: to load apps for the currently selected team right after login.
 @param			completionHandler Called on the main thread, contains a dictionary consisting of the keys "teams" (an array of dictionaries describing the teams), "teamID" (the currently selected team), "apps" (an array of dictionaries describing the apps of the currently selected team).
 */
- (void)_loadSessionDataAfterLoginWithCompletionHandler:(void (^)(NSDictionary *info, NSError *error))completionHandler;

/*!
 @method		_sessionDataWithCompletionHandler:
 @abstract		Actually loads the session information (teams, current team, logged in user)
 */
- (void)_sessionDataWithCompletionHandler:(void (^)(NSDictionary *sessionDict, NSError *error))completionHandler;

/*!
 @method		_switchToTeamWithID:completionHandler:
 @abstract		Switches to the team specified by @c teamID.
 @param			teamID The teamID to which we want to switch to. Best taken from the session data (see @c -_loadSessionDataAfterLoginWithCompletionHandler:).
 @param			completionHandler Called on the main thread. Returns YES if switched successfully, otherwise NO.
 */
- (void)_switchToTeamWithID:(NSNumber *)teamID completionHandler:(void(^)(BOOL switched, NSError *error))completionHandler;

/*!
 @method		_appsForCurrentTeamWithCompletionHandler:
 @abstract		Loads the apps for the currently selected team. Might return a cached value if apps for the current team have already been loaded.
 @param			completionHandler Called on the main thread, this returns dictionaries that describe the apps, or nil if an error occurred.
 */
- (void)_appsForCurrentTeamWithCompletionHandler:(void (^)(NSArray <NSDictionary *> *apps, NSError *error))completionHandler;

/*!
 @method		_recursivelyLoadPromoCodeHistoryForAppWithID:creationRequestDate:completionHandler:
 @abstract		Recursively calls itself until the requested promo codes can be retrieved using @c _promoCodeHistoryForAppWithID:completionHandler.
 @discussion	Calls itself every 10 seconds at the most, as to not flood Apple's servers.
 @param			appID The ID of the app we're trying to retrieve the newly created promo codes for.
 @param			creationRequestDate The date when we first called this method. Used as a metric to find the newly created codes.
 @param			completionHandler Called on the main thread, it contains the promo code info or nil, if an error occurred.
 */
- (void)_recursivelyLoadPromoCodeHistoryForAppWithID:(NSString *)appID creationRequestDate:(NSDate *)creationRequestDate completionHandler:(void (^)(NSArray <NSDictionary *> *promoCodes, NSError *error))completionHandler;

/*!
 @method		_promoCodeHistoryForAppWithID:completionHandler:
 @abstract		Retrieves the promo code history for the specified app.
 @param			appID The ID of the app we want to retrieve the promo code history for.
 @param			completionHandler Called on the main thread, it contains the history, or nil if an error occurred.
 */
- (void)_promoCodeHistoryForAppWithID:(NSString *)appID completionHandler:(void (^)(NSArray <NSDictionary *> *historyDicts, NSError *error))completionHandler;

@end

@implementation ESSAppStoreConnectAPI

static ESSAppStoreConnectAPI *_shAPI = nil;
+ (instancetype)sharedAPI
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		_shAPI = [[[self class] alloc] init];
	});
	
	return _shAPI;
}

- (instancetype)init
{
	if (self = [super init])
	{
		self.cachedAppsKeyedByTeamID = [[NSMutableDictionary alloc] init];
		return self;
	}
	
	return nil;
}

#pragma mark - Login

- (void)loginWithUsername:(NSString *)username
				 password:(NSString *)password
		completionHandler:(void (^)(BOOL loggedIn, BOOL needsTwoFactorAuth, NSDictionary *info, NSError *error))completionHandler
{
	NSAssert(completionHandler != nil, @"completionHandler may not be nil");
	
	if (username.length == 0 || password.length == 0)
	{
		completionHandler(NO, NO, nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_LOGIN code:ESSASCAPIErrorCodeMalformedRequest userInfo:nil]);
		return;
	}
	
	//first, retrieve authServiceKey / Apple Widget Key
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://appstoreconnect.apple.com/olympus/v1/app/config?hostname=itunesconnect.apple.com"]];
	NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
																 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
																	 dispatch_async(dispatch_get_main_queue(), ^{
																		 if (data == nil || response == nil || error != nil)
																		 {
																			 completionHandler(NO, NO, nil, error);
																			 return;
																		 }
																		 
																		 NSError *jsonError = nil;
																		 NSDictionary *retDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
																		 if (retDict == nil || ![retDict isKindOfClass:[NSDictionary class]])
																		 {
																			 completionHandler(NO, NO, nil, jsonError);
																			 return;
																		 }
																		 
																		 self.authServiceKey = retDict[@"authServiceKey"];
																		 
																		 if (self.authServiceKey.length == 0)
																		 {
																			 completionHandler(NO, NO, nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_LOGIN code:ESSASCAPIErrorCodeServiceKeyMissing userInfo:nil]);
																			 return;
																		 }
																		 
																		 //now start actual sign in process
																		 NSDictionary *loginDict = @{@"accountName":username,
																									 @"password":password,
																									 @"rememberMe":@(YES)
																									 };
																		 NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://idmsa.apple.com/appleauth/auth/signin"]];
																		 
																		 jsonError = nil;
																		 NSData *loginJson = [NSJSONSerialization dataWithJSONObject:loginDict options:NSJSONWritingPrettyPrinted error:&jsonError];
																		 if (loginJson == nil)
																		 {
																			 completionHandler(NO, NO, nil, jsonError);
																			 return;
																		 }
																		 req.HTTPBody = loginJson;
																		 req.HTTPMethod = @"POST";
																		 req.HTTPShouldHandleCookies = YES;
																		 [self _updateHeadersForRequest:req additionalFields:nil];
																		 
																		 NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
																																	  completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
																																		  dispatch_async(dispatch_get_main_queue(), ^{
																																			  NSHTTPURLResponse *resp = (NSHTTPURLResponse *)response;
																																			  if (data == nil || resp == nil || error != nil)
																																			  {
																																				  completionHandler(NO, NO, nil, error);
																																				  return;
																																			  }
																																			  
																																			  if (resp.statusCode == 409)
																																			  {
																																				  //two-factor or two-step authentication in effect, auth-code possibly already sent to user (via push to device or sms to trusted number)
																																				  NSString *scnt = resp.allHeaderFields[@"scnt"];
																																				  NSString *xappleidsessionid = resp.allHeaderFields[@"X-Apple-ID-Session-Id"];
																																				  if (scnt.length == 0 ||
																																					  xappleidsessionid.length == 0)
																																				  {
																																					  completionHandler(NO, NO, nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_LOGIN code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]);
																																					  return;
																																				  }
																																				  self.tfaScnt = scnt;
																																				  self.tfaAppleIDSessionID = xappleidsessionid;
																																				  
																																				  NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://idmsa.apple.com/appleauth/auth"]];
																																				  req.HTTPMethod = @"GET";
																																				  [self _updateHeadersForRequest:req
																																								additionalFields:@{@"X-Apple-Id-Session-Id":self.tfaAppleIDSessionID,
																																												   @"scnt":self.tfaScnt
																																												   }];
																																				  //request auth info from user
																																				  NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
																																																			   completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
																																																				   dispatch_async(dispatch_get_main_queue(), ^{
																																																					   if (data == nil || response == nil || error != nil)
																																																					   {
																																																						   completionHandler(NO, YES, nil, error);
																																																						   return;
																																																					   }
																																																					   /*
																																																						There are, as far as I could test, four ways to go:
																																																						1) an error occurs - end
																																																						2) one phone number and no trusted devices are stored -> code sent via sms to phone number right away
																																																							but need option to re-send code via sms
																																																						3) more than one phone number and no trusted devices -> code not automatically sent, needs selection of where to send code to
																																																						4) any number of phone numbers, but have trusted devices -> code sent to devices right away
																																																							but need option to re-send code or send via sms
																																																						*/
																																																					   
																																																					   NSError *jsonError = nil;
																																																					   NSDictionary *_dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
																																																					   if (_dict == nil || ![_dict isKindOfClass:[NSDictionary class]] ||
																																																						   ([_dict[@"trustedDevices"] count] == 0 && [_dict[@"trustedPhoneNumbers"] count] == 0) ||
																																																						   jsonError != nil)
																																																					   {
																																																						   completionHandler(NO, YES, nil, (jsonError ? :[NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_LOGIN code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]));
																																																						   return;
																																																					   }
																																																					   
																																																					   NSDictionary *securityCodeDict = _dict[@"securityCode"];
																																																					   if ([securityCodeDict[@"securityCodeLocked"] boolValue] == YES ||
																																																						   [securityCodeDict[@"tooManyCodesSent"] boolValue] == YES ||
																																																						   [securityCodeDict[@"tooManyCodesValidated"] boolValue] == YES)
																																																					   {
																																																						   ESSASCAPIErrorCode code = ESSASCAPIErrorCodeUnexpectedReply;
																																																						   if ([securityCodeDict[@"securityCodeLocked"] boolValue] == YES)
																																																							   code = ESSASCAPIErrorCodeSecurityCodeLocked;
																																																						   else if ([securityCodeDict[@"tooManyCodesSent"] boolValue] == YES)
																																																							   code = ESSASCAPIErrorCodeTooManyCodesSent;
																																																						   else if ([securityCodeDict[@"tooManyCodesValidated"] boolValue] == YES)
																																																							   code = ESSASCAPIErrorCodeTooManyCodesValidated;
																																																						   completionHandler(NO, YES, nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_LOGIN code:code userInfo:nil]);
																																																						   return;
																																																					   }
																																																					   
																																																					   NSDictionary *infoDict = @{@"securityCode":securityCodeDict,
																																																												  @"phoneNumbers":_dict[@"trustedPhoneNumbers"],
																																																												  @"didSendCode":@(YES),
																																																												  @"wasTrustedDeviceCode":@((_dict[@"noTrustedDevices"] == nil || [_dict[@"noTrustedDevices"] boolValue] == NO)),
																																																												  @"scnt":self.tfaScnt,
																																																												  @"AppleIDSessionID":self.tfaAppleIDSessionID
																																																												  };
																																																					   
																																																					   if ((_dict[@"mode"] != nil && [_dict[@"mode"] isEqualToString:@"sms"] &&
																																																							[_dict[@"phoneNumber"] allKeys].count != 0 &&
																																																							securityCodeDict.allKeys.count != 0 &&
																																																							[_dict[@"noTrustedDevices"] boolValue] == YES) || //an sms was sent
																																																						   (_dict[@"noTrustedDevices"] == nil ||
																																																							[_dict[@"noTrustedDevices"] boolValue] == NO)) //a code was pushed to the account's trusted devices
																																																					   {
																																																						   //code was sent right away
																																																						   if ([infoDict[@"wasTrustedDeviceCode"] boolValue] == NO)
																																																						   {
																																																							   NSMutableDictionary *dic = infoDict.mutableCopy;
																																																							   dic[@"resendInfo"] = @{@"phoneID":dic[@"phoneNumber"][@"id"]};
																																																							   infoDict = dic.copy;
																																																						   }
																																																						   completionHandler(NO, YES, infoDict, nil);
																																																						   return;
																																																					   }
																																																					   
																																																					   NSMutableDictionary *mDict = infoDict.mutableCopy;
																																																					   mDict[@"didSendCode"] = @(NO);
																																																					   
																																																					   //the code was not sent right away, need to present the user with a selection for their preferred phone number
																																																					   completionHandler(NO, YES, mDict.copy, nil);
																																																				   });
																																																			   }];
																																				  [task resume];
																																				  return;
																																			  } else if (resp.statusCode != 200)
																																			  {
																																				  //something else went wrong.
																																				  completionHandler(NO, NO, nil, (error != nil ? error:[NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_LOGIN code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]));
																																				  return;
																																			  }
																																			  
																																			  //we're already logged in - either 2FA is not enabled, or cookies are still valid from previous session
																																			  NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]; //returns {"authType":"non-sa";}
																																			  if (dict == nil || ![dict isKindOfClass:[NSDictionary class]])
																																			  {
																																				  //no dict returned
																																				  completionHandler(NO, NO, nil, (error != nil ? error:[NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_LOGIN code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]));
																																				  return;
																																			  }
																																			  
																																			  if (dict[@"serviceErrors"] != nil)
																																			  {
																																				  NSLog(@"*** received an error - possibly login: %@",dict[@"serviceErrors"]);
																																				  completionHandler(NO, NO, nil, (error != nil ? error:[NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_LOGIN code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]));
																																				  return;
																																			  }
																																			  
																																			  //retrieve session data (returns teams, apps and user)
																																			  [self _loadSessionDataAfterLoginWithCompletionHandler:^(NSDictionary *info, NSError *error) {
																																				  if (info == nil || error != nil)
																																				  {
																																					  completionHandler(YES, NO, nil, error);
																																					  return;
																																				  }
																																				  
																																				  completionHandler(YES, NO, info, nil);
																																			  }];
																																		  });
																																	  }];
																		 [task resume];
																	 });
																 }];
	[task resume];
}

- (void)resend2FACodeWithPhoneID:(NSNumber *)phoneID completionHandler:(void (^)(BOOL resent, NSError *err))completionHandler
{
	NSAssert(completionHandler != nil, @"completionHandler may not be nil");
	
	if (phoneID == nil)
	{
		completionHandler(NO, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_LOGIN code:ESSASCAPIErrorCodeMalformedRequest userInfo:nil]);
		return;
	}
	
	NSDictionary *body = @{@"phoneNumber":@{@"id":phoneID},
						   @"mode":@"sms"
						   };
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://idmsa.apple.com/appleauth/verify/phone"]];
	req.HTTPMethod = @"PUT";
	[self _updateHeadersForRequest:req
				  additionalFields:@{@"X-Apple-Id-Session-Id":self.tfaAppleIDSessionID,
									 @"scnt":self.tfaScnt
									 }];
	
	NSError *jsonError = nil;
	NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
	if (bodyData == nil)
	{
		completionHandler(NO, jsonError);
		return;
	}
	
	req.HTTPBody = bodyData;
	
	NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
																 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
																	 dispatch_async(dispatch_get_main_queue(), ^{
																		 if (data == nil || response == nil || error != nil)
																		 {
																			 completionHandler(NO, error);
																			 return;
																		 }
																		 
																		 NSString *retStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
																		 if (retStr.length == 0)
																		 {
																			 completionHandler(NO, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_LOGIN code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]);
																			 return;
																		 }
																		 
																		 if ([retStr rangeOfString:@"sectionErrorKeys" options:NSCaseInsensitiveSearch].location != NSNotFound ||
																			 [retStr rangeOfString:@"validationErrors" options:NSCaseInsensitiveSearch].location != NSNotFound ||
																			 [retStr rangeOfString:@"serviceErrors" options:NSCaseInsensitiveSearch].location != NSNotFound ||
																			 [retStr rangeOfString:@"sectionInfoKeys" options:NSCaseInsensitiveSearch].location != NSNotFound ||
																			 [retStr rangeOfString:@"sectionWarningKeys" options:NSCaseInsensitiveSearch].location != NSNotFound)
																		 {
																			 //found an error
																			 completionHandler(NO, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_LOGIN code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]);
																			 return;
																		 }
																		 
																		 completionHandler(YES, nil);
																	 });
																 }];
	[task resume];
}

- (void)finish2FAWithCode:(NSString *)code phoneID:(NSNumber *)phoneID completionHandler:(void (^)(BOOL loggedIn, NSDictionary *info, NSError *error))completionHandler
{
	NSAssert(completionHandler != nil, @"completionHandler may not be nil");
	
	if (code.length == 0)
	{
		completionHandler(NO, nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_LOGIN code:ESSASCAPIErrorCodeMalformedRequest userInfo:nil]);
		return;
	}
	
	NSURL *url = nil;
	NSDictionary *body = nil;
	
	if (phoneID == nil)
	{
		url = [NSURL URLWithString:@"https://idmsa.apple.com/appleauth/auth/verify/trusteddevice/securitycode"];
		body = @{@"securityCode":@{@"code":code}};
	} else
	{
		//was phone code
		url = [NSURL URLWithString:@"https://idmsa.apple.com/appleauth/auth/verify/phone/securitycode"];
		body = @{@"securityCode":@{@"code":code},
				 @"phoneNumber":@{@"id":phoneID},
				 @"mode":@"sms"
				 };
	}
	
	
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
	req.HTTPMethod = @"POST";
	[self _updateHeadersForRequest:req
				  additionalFields:@{@"X-Apple-Id-Session-Id":self.tfaAppleIDSessionID,
									 @"scnt":self.tfaScnt
									 }];
	NSError *jsonError = nil;
	NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
	if (bodyData == nil)
	{
		completionHandler(NO, nil, jsonError);
		return;
	}
	
	req.HTTPBody = bodyData;
	
	NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
																 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
																	 dispatch_async(dispatch_get_main_queue(), ^{
																		 if (data == nil || response == nil || error != nil)
																		 {
																			 completionHandler(NO, nil, error);
																			 return;
																		 }
																		 
																		 NSString *retStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
																		 
																		 if ([retStr rangeOfString:@"sectionErrorKeys" options:NSCaseInsensitiveSearch].location != NSNotFound ||
																			 [retStr rangeOfString:@"validationErrors" options:NSCaseInsensitiveSearch].location != NSNotFound ||
																			 [retStr rangeOfString:@"serviceErrors" options:NSCaseInsensitiveSearch].location != NSNotFound ||
																			 [retStr rangeOfString:@"sectionInfoKeys" options:NSCaseInsensitiveSearch].location != NSNotFound ||
																			 [retStr rangeOfString:@"sectionWarningKeys" options:NSCaseInsensitiveSearch].location != NSNotFound)
																		 {
																			 //found an error
																			 completionHandler(NO, nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_LOGIN code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]);
																			 return;
																		 }
																		 
																		 NSMutableURLRequest *_req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://idmsa.apple.com/appleauth/auth/2sv/trust"]];
																		 _req.HTTPMethod = @"GET";
																		 [self _updateHeadersForRequest:_req
																					   additionalFields:@{@"X-Apple-Id-Session-Id":self.tfaAppleIDSessionID,
																										  @"scnt":self.tfaScnt
																										  }];
																		 NSURLSessionDataTask *_task = [[NSURLSession sharedSession] dataTaskWithRequest:_req
																																	   completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
																																		   if (data == nil || response == nil || error != nil)
																																		   {
																																			   completionHandler(NO, nil, error);
																																			   return;
																																		   }
																																		   
																																		   [self _loadSessionDataAfterLoginWithCompletionHandler:^(NSDictionary *info, NSError *error) {
																																			   if (info == nil || error != nil)
																																			   {
																																				   completionHandler(NO, nil, error);
																																				   return;
																																			   }
																																			   
																																			   self.tfaAppleIDSessionID = self.tfaScnt = nil; //don't need them anymore from this point on
																																			   completionHandler(YES, info, nil);
																																		   }];
																																	   }];
																		 [_task resume];
																	 });
																 }];
	[task resume];
}

- (void)checkLoginWithCompletionHandler:(void (^)(BOOL loggedIn, NSArray <NSDictionary *> *teams, NSNumber *currentTeamID, NSArray <NSDictionary *> *apps, NSError *error))completionHandler
{
	NSAssert(completionHandler != nil, @"completionHandler may not be nil");
	
	if (!self.isLoggedIn || self.currentTeamID == nil || self.personID == nil)
	{
		completionHandler(NO, nil, nil, nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_LOGIN code:ESSASCAPIErrorCodeMalformedRequest userInfo:nil]);
		return;
	}
	
	[self _sessionDataWithCompletionHandler:^(NSDictionary *sessionDict, NSError *error) {
		completionHandler(sessionDict != nil && error == nil, self.cachedTeams, self.currentTeamID, self.cachedAppsKeyedByTeamID[[NSString stringWithFormat:@"%ld",self.currentTeamID.unsignedIntegerValue]], error);
	}];
}

#pragma mark - App Retrieval

- (void)appsForTeamWithProviderID:(NSNumber *)providerID
				completionHandler:(void (^)(NSArray *apps, NSError *error))completionHandler
{
	NSAssert(completionHandler != nil, @"completionHandler may not be nil");
	
	if (!self.isLoggedIn)
	{
		completionHandler(nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_APPS code:ESSASCAPIErrorCodeNotLoggedIn userInfo:nil]);
		return;
	}
	
	if (providerID == nil)
	{
		completionHandler(nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_APPS code:ESSASCAPIErrorCodeMalformedRequest userInfo:nil]);
		return;
	}
	
	/*if (self.cachedAppsKeyedByTeamID[[NSString stringWithFormat:@"%ld",providerID.unsignedIntegerValue]] != nil)
	{
		completionHandler(self.cachedAppsKeyedByTeamID[[NSString stringWithFormat:@"%ld",providerID.unsignedIntegerValue]], nil);
		return;
	}*/
	
	if ([providerID isEqualToNumber:self.currentTeamID])
	{
		[self _appsForCurrentTeamWithCompletionHandler:completionHandler];
		return;
	}
	
	[self _switchToTeamWithID:providerID
			completionHandler:^(BOOL switched, NSError *error) {
				if (!switched || error != nil)
				{
					completionHandler(nil, error);
					return;
				}
				
				[self _appsForCurrentTeamWithCompletionHandler:completionHandler];
			}];
}

#pragma mark - Promo Code Info and Creation

- (void)promoCodeInfoForAppWithID:(NSString *)appID
				completionHandler:(void(^)(NSDictionary *info, NSError *error))completionHandler
{
	NSAssert(completionHandler != nil, @"completionHandler may not be nil");
	
	if (!self.isLoggedIn)
	{
		completionHandler(nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_PROMOCODES code:ESSASCAPIErrorCodeNotLoggedIn userInfo:nil]);
		return;
	}
	
	if (appID.length == 0)
	{
		completionHandler(nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_PROMOCODES code:ESSASCAPIErrorCodeMalformedRequest userInfo:nil]);
		return;
	}
	
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://appstoreconnect.apple.com/WebObjects/iTunesConnect.woa/ra/apps/%@/promocodes/versions",appID]]];
	req.HTTPMethod = @"GET";
	req.HTTPShouldHandleCookies = YES;
	[self _updateHeadersForRequest:req additionalFields:nil];
	NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
																 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
																	 dispatch_async(dispatch_get_main_queue(), ^{
																		 if (data == nil || response == nil || error != nil)
																		 {
																			 completionHandler(nil, error);
																			 return;
																		 }
																		 
																		 NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
																		 if (dict == nil || ![dict isKindOfClass:[NSDictionary class]])
																		 {
																			 completionHandler(nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_PROMOCODES code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]);
																			 return;
																		 }
																		 
																		 NSDictionary *dataDict = dict[@"data"];
																		 if (![dataDict isKindOfClass:[NSDictionary class]])
																		 {
																			 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
																				 [self promoCodeInfoForAppWithID:appID completionHandler:completionHandler];
																			 });
																			 return;
																		 }
																		 NSArray *versions = dataDict[@"versions"];
																		 if (![versions isKindOfClass:[NSArray class]] || versions.count == 0)
																		 {
																			 completionHandler(@{}, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_PROMOCODES code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]);
																			 return;
																		 }
																		 
																		 NSDictionary *chosenDict = versions.firstObject;
																		 
																		 NSDictionary *returnDict = @{@"version":chosenDict[@"version"],
																									  @"versionID":chosenDict[@"id"],
																									  @"contractFilename":chosenDict[@"contractFileName"],
																									  @"codesLeft":@([chosenDict[@"maximumNumberOfCodes"] unsignedIntegerValue] - [chosenDict[@"numberOfCodes"] unsignedIntegerValue])
																									  };
																		 
																		 completionHandler(returnDict, nil);
																	 });
																 }];
	[task resume];
}

- (void)requestPromoCodesForAppWithID:(NSString *)appID
							versionID:(NSString *)versionID
							 quantity:(NSUInteger)quantity
					 contractFileName:(NSString *)contractFilename
					completionHandler:(void (^)(NSArray <NSDictionary *> *promoCodes, NSError *error))completionHandler
{
	NSAssert(completionHandler != nil, @"completionHandler may not be nil");
	
	if (!self.isLoggedIn)
	{
		completionHandler(nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_PROMOCODES code:ESSASCAPIErrorCodeNotLoggedIn userInfo:nil]);
		return;
	}
	
	if (appID == nil || versionID == nil || quantity == 0 || contractFilename.length == 0)
	{
		completionHandler(nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_PROMOCODES code:ESSASCAPIErrorCodeMalformedRequest userInfo:nil]);
		return;
	}
	
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://appstoreconnect.apple.com/WebObjects/iTunesConnect.woa/ra/apps/%@/promocodes/versions/",appID]]];
	req.HTTPMethod = @"POST";
	[self _updateHeadersForRequest:req additionalFields:nil];
	req.HTTPShouldHandleCookies = YES;
	
	NSDictionary *jsonDict = @{@"numberOfCodes":@(quantity),
							   @"agreedToContract":@(YES),
							   @"versionId":versionID,
							   };
	NSArray *jsonArray = @[jsonDict];
	
	NSError *jsonError = nil;
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonArray options:0 error:&jsonError];
	if (jsonData == nil)
	{
		completionHandler(nil, jsonError);
		return;
	}
	
	req.HTTPBody = jsonData;
	
	NSDate *creationRequestDate = [NSDate dateWithTimeIntervalSinceNow:-1];
	NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
																 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
																	 dispatch_async(dispatch_get_main_queue(), ^{
																		 if (data == nil || response == nil || error != nil)
																		 {
																			 completionHandler(nil, error);
																			 return;
																		 }
																		 
																		 NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
																		 if (dict == nil || ![dict isKindOfClass:[NSDictionary class]])
																		 {
																			 completionHandler(nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_PROMOCODES code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]);
																			 return;
																		 }
																		 
																		 NSDictionary *dataDict = dict[@"data"];
																		 if (data == nil)
																		 {
																			 completionHandler(nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_PROMOCODES code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]);
																			 return;
																		 }
																		 
																		 NSArray *successfulArray = dataDict[@"successful"];
																		 if (successfulArray.count <= 0)
																		 {
																			 completionHandler(nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_PROMOCODES code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]);
																			 return;
																		 }
																		 
																		 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
																			 //promo code creation apparently takes a couple of seconds on Apple's servers, so it also takes a little while until they show up in the promo code history
																			 //to minimize traffic, we wait 5 seconds after the promo code creation, and then start our recursive polling for the newly created codes.
																			 [self _recursivelyLoadPromoCodeHistoryForAppWithID:appID creationRequestDate:creationRequestDate completionHandler:completionHandler];
																		 });
																	 });
																 }];
	[task resume];
}

#pragma mark - Helper Methods

- (BOOL)isLoggedIn
{
	return (self.authServiceKey.length != 0 && self.personID != nil);
}

- (void)_updateHeadersForRequest:(NSMutableURLRequest *)req additionalFields:(NSDictionary *)additionalFields
{
	if (req == nil)
		return;
	
	if ([req.HTTPMethod isEqualToString:@"POST"] ||
		[req.HTTPMethod isEqualToString:@"PUT"])
		[req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	
	if (self.authServiceKey != nil)
		[req setValue:self.authServiceKey forHTTPHeaderField:@"X-Apple-Widget-Key"];
	
	[req setValue:@"itc" forHTTPHeaderField:@"X-Csrf-Itc"];
	
	if (additionalFields[@"JUSTPOSTFIELDS"] != nil)
		return;
	
	[req setValue:@"application/json, text/javascript" forHTTPHeaderField:@"Accept"];
	[req setValue:@"keep-alive" forHTTPHeaderField:@"Connection"];
	[req setValue:@"PromoCodes for Mac and iOS by Eternal Storms Software" forHTTPHeaderField:@"User-Agent"];
	[req setValue:@"itc" forHTTPHeaderField:@"X-Csrf-Itc"];

	if (additionalFields.allKeys.count != 0)
	{
		for (NSString *key in additionalFields.allKeys)
		{
			[req setValue:additionalFields[key] forHTTPHeaderField:key];
		}
	}
}

- (void)_loadSessionDataAfterLoginWithCompletionHandler:(void (^)(NSDictionary *info, NSError *error))completionHandler
{
	NSAssert(completionHandler != nil, @"completionHandler may not be nil");
	
	[self _sessionDataWithCompletionHandler:^(NSDictionary *sessionDict, NSError *error) {
		if (sessionDict == nil || error != nil)
		{
			completionHandler(nil, error);
			return;
		}
		
		NSMutableArray *teams = [NSMutableArray array];
		for (NSDictionary *dict in sessionDict[@"availableProviders"])
		{
			NSMutableDictionary *newTeam = [NSMutableDictionary dictionary];
			if (dict[@"name"] != nil)
				newTeam[@"name"] = dict[@"name"];
			if (dict[@"providerId"] != nil)
				newTeam[@"providerID"] = dict[@"providerId"];
			if (dict[@"contentTypes"] != nil)
				newTeam[@"contentTypes"] = dict[@"contentTypes"];
			if (dict[@"publicProviderId"] != nil)
				newTeam[@"publicProviderId"] = dict[@"publicProviderId"];
			if (dict[@"subType"] != nil)
				newTeam[@"subType"] = dict[@"subType"];
			[teams addObject:newTeam.copy];
		}
		
		self.personID = sessionDict[@"user"][@"prsId"];
		self.currentTeamID = sessionDict[@"provider"][@"providerId"];
		self.currentPublicProviderID = sessionDict[@"provider"][@"publicProviderId"];
		
		if (self.personID == nil || self.currentTeamID == nil)
		{
			NSLog(@"*** personID or currentTeamID couldn't be retrieved");
			completionHandler(nil, error);
			return;
		}
		
		[teams sortUsingComparator:^NSComparisonResult(NSDictionary * _Nonnull obj1, NSDictionary * _Nonnull obj2) {
			return [obj1[@"name"] compare:obj2[@"name"] options:NSNumericSearch];
		}];
		
		self.cachedTeams = teams;
		
		[self appsForTeamWithProviderID:self.currentTeamID
					  completionHandler:^(NSArray<NSDictionary *> *apps, NSError *error) {
						  if (apps == nil || error != nil)
						  {
							  completionHandler(nil, error);
							  return;
						  }
						  
						  completionHandler(@{@"teams":self.cachedTeams,
											  @"teamID":self.currentTeamID,
											  @"apps":apps},
											nil);
					  }];
	}];
}

- (void)_sessionDataWithCompletionHandler:(void (^)(NSDictionary *sessionDict, NSError *error))completionHandler
{
	NSAssert(completionHandler != nil && self.authServiceKey.length != 0, @"completionHandler, identificationCookie and authServiceKey may not be nil");
	
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://appstoreconnect.apple.com/olympus/v1/session"]];
	req.HTTPShouldHandleCookies = YES;
	[self _updateHeadersForRequest:req additionalFields:nil];
	NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (data == nil || response == nil || error != nil)
			{
				completionHandler(nil, error);
				return;
			}
			
			NSDictionary *sessionDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
			if (sessionDict == nil || ![sessionDict isKindOfClass:[NSDictionary class]])
			{
				completionHandler(nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_LOGIN code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]);
				return;
			}
			
			completionHandler(sessionDict, nil);
		});
	}];
	[task resume];
}

- (void)_switchToTeamWithID:(NSNumber *)teamID completionHandler:(void(^)(BOOL switched, NSError *error))completionHandler
{
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://appstoreconnect.apple.com/olympus/v1/providerSwitchRequests"]];
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
	req.HTTPShouldHandleCookies = YES;
	req.HTTPMethod = @"POST";
	NSString *publicTeamID = nil;
	for (NSDictionary *dic in self.cachedTeams)
	{
		if ([dic[@"providerID"] isEqualToNumber:teamID])
		{
			publicTeamID = dic[@"publicProviderId"];
			break;
		}
	}
	
	if (publicTeamID == nil)
	{
		completionHandler(NO, nil);
		return;
	}
	
	[self _updateHeadersForRequest:req additionalFields:@{@"JUSTPOSTFIELDS":@""}];
	NSDictionary *jsonDict = @{@"data":@{
		@"type":@"providerSwitchRequests",
		@"relationships":@{
			@"provider":@{
				@"data":@{
					@"type":@"providers",
					@"id":publicTeamID
				}
			}
		}
	}
	};
	NSError *jsonError = nil;
	NSData *bodyData = [NSJSONSerialization dataWithJSONObject:jsonDict options:NSJSONWritingPrettyPrinted error:&jsonError];
	if (bodyData == nil)
	{
		completionHandler(NO, jsonError);
		return;
	}
	req.HTTPBody = bodyData;
	
	NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
																 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
																	 dispatch_async(dispatch_get_main_queue(), ^{
																		 if (data == nil || response == nil || error != nil)
																		 {
																			 completionHandler(NO, error);
																			 return;
																		 }
																		 
																		 NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
																		 if (dict == nil || ![dict isKindOfClass:[NSDictionary class]])
																		 {
																			 completionHandler(NO, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_APPS code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]);
																			 return;
																		 }
																		 
																		 NSDictionary *webSessionData = dict[@"data"];
																		 
																		 if (webSessionData == nil ||
																			 webSessionData.allKeys.count == 0 ||
																			 webSessionData[@"id"] == nil ||
																			 webSessionData[@"type"] == nil)
																		 {
																			 completionHandler(NO, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_APPS code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]);
																			 return;
																		 }
																		 
																		 self.currentTeamID = teamID;
																		 self.currentPublicProviderID = webSessionData[@"id"];
																		 
																		 completionHandler(YES, nil);
																	 });
																 }];
	[task resume];
}

- (void)_appsForCurrentTeamWithCompletionHandler:(void (^)(NSArray <NSDictionary *> *apps, NSError *error))completionHandler
{
	NSAssert(completionHandler != nil, @"completionHandler may not be nil");
	
	if (self.cachedAppsKeyedByTeamID[[NSString stringWithFormat:@"%ld",self.currentTeamID.unsignedIntegerValue]] != nil)
	{
		completionHandler(self.cachedAppsKeyedByTeamID[[NSString stringWithFormat:@"%ld",self.currentTeamID.unsignedIntegerValue]], nil);
		return;
	}
	
	//NSString *urlStr = @"https://appstoreconnect.apple.com/iris/v1/apps?limit=100";
	NSString *urlStr = @"https://appstoreconnect.apple.com/WebObjects/iTunesConnect.woa/ra/apps/manageyourapps/summary/v2";
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
	req.HTTPShouldHandleCookies = YES;
	req.HTTPMethod = @"GET";
	[self _updateHeadersForRequest:req additionalFields:nil];
	
	NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
																 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
																	 dispatch_async(dispatch_get_main_queue(), ^{
																		 if (data == nil || response == nil || error != nil)
																		 {
																			 completionHandler(nil, error);
																			 return;
																		 }
																		 
																		 NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
																		 if (dict == nil || ![dict isKindOfClass:[NSDictionary class]])
																		 {
																			 completionHandler(nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_APPS code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]);
																			 return;
																		 }
																		 
																		 NSArray *appIDs = dict[@"data"][@"summaries"];
																		 
																		 NSMutableArray *finalArray = [NSMutableArray array];
																		 for (NSDictionary *dict in appIDs)
																		 {
																			 if ([[[dict[@"versionSets"] firstObject] objectForKey:@"type"] isEqualToString:@"BUNDLE"] ||
																				 [[[dict[@"buildVersionSets"] firstObject] objectForKey:@"type"] isEqualToString:@"BUNDLE"])
																				 continue;
																			 
																			 NSArray <NSDictionary *> *versionSets = dict[@"versionSets"];
																			 NSString *platform = @"";
																			 for (NSDictionary *version in versionSets)
																			 {
																				 platform = version[@"platformString"]; //'osx' or 'ios' or 'appletvos'
																				 if (platform.length != 0)
																					 break;
																			 }
																			 if (platform.length == 0)
																			 {
																				 versionSets = dict[@"buildVersionSets"];
																				 for (NSDictionary *version in versionSets)
																				 {
																					 platform = version[@"platformString"]; //'osx' or 'ios' or 'appletvos'
																					 if (platform.length != 0)
																						 break;
																				 }
																			 }
																			 NSDictionary *newDict = @{@"id":dict[@"adamId"],
																									   @"name":dict[@"name"],
																									   @"bundleID":dict[@"bundleId"],
																									   @"sku":dict[@"vendorId"],
																									   @"platform":platform
																									   };
																			 [finalArray addObject:newDict];
																		 }
																		 
																		 [finalArray sortUsingComparator:^NSComparisonResult(NSDictionary * _Nonnull obj1, NSDictionary * _Nonnull obj2) {
																			 return [obj1[@"name"] compare:obj2[@"name"] options:NSNumericSearch];
																		 }];
																		 
																		 [self.cachedAppsKeyedByTeamID setObject:finalArray.copy forKey:[NSString stringWithFormat:@"%ld",self.currentTeamID.unsignedIntegerValue]];
																		 
																		 completionHandler(finalArray.copy, nil);
																	 });
																 }];
	[task resume];
}

- (void)_recursivelyLoadPromoCodeHistoryForAppWithID:(NSString *)appID creationRequestDate:(NSDate *)creationRequestDate completionHandler:(void (^)(NSArray <NSDictionary *> *promoCodes, NSError *error))completionHandler
{
	NSDate *lastRequestDate = [NSDate date];
	[self _promoCodeHistoryForAppWithID:appID
					  completionHandler:^(NSArray <NSDictionary *> *historyDicts, NSError *error) {
						  if (historyDicts.count == 0 || error != nil)
						  {
							  completionHandler(nil, error);
							  return;
						  }
						  
						  NSMutableArray *finalCodes = [NSMutableArray array];
						  for (NSDictionary *codeDict in historyDicts)
						  {
							  NSArray *codes = codeDict[@"codes"];
							  if (codes.count == 0)
								  continue;
							  
							  long long creationDateNanoseconds = [codeDict[@"effectiveDate"] longLongValue];
							  NSTimeInterval creationDateTimeInterval = creationDateNanoseconds/1000;
							  NSDate *creationDate = [NSDate dateWithTimeIntervalSince1970:creationDateTimeInterval];
							  if ([[creationDate laterDate:creationRequestDate] isEqualToDate:creationRequestDate])
							  {
								  //these promo codes were created before we requested them here - ignore.
								  continue;
							  }
							  
							  long long expDateNanoseconds = [codeDict[@"expirationDate"] longLongValue];
							  NSTimeInterval expDateTimeInterval = expDateNanoseconds/1000;
							  NSDate *expDate = [NSDate dateWithTimeIntervalSince1970:expDateTimeInterval];
							  
							  for (NSString *code in codes)
							  {
								  NSDictionary *newCodeDict = @{@"code":code,
																@"creationDate":creationDate,
																@"expirationDate":expDate,
																@"requestId":codeDict[@"id"],
																@"platform":codeDict[@"version"][@"platform"], //osx, ios or appletvos
																@"version":codeDict[@"version"][@"version"]
																};
								  [finalCodes addObject:newCodeDict];
							  }
						  }
						  
						  if (finalCodes.count == 0)
						  {
							  NSTimeInterval minTimeToHavePassed = 10.0;
							  NSTimeInterval time = minTimeToHavePassed - ([[NSDate date] timeIntervalSinceDate:lastRequestDate]);
							  if (time < minTimeToHavePassed)
								  time = 0.01;
							  //as to not the "flood" the server with too many requests, at least 'minTimeToHavePassed' seconds have to have passed since the last request. maybe raise that at some point.
							  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(time * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
								  [self _recursivelyLoadPromoCodeHistoryForAppWithID:appID creationRequestDate:creationRequestDate completionHandler:completionHandler];
							  });
							  return;
						  }
						  
						  completionHandler(finalCodes.copy, nil);
					  }];
}

- (void)_promoCodeHistoryForAppWithID:(NSString *)appID completionHandler:(void (^)(NSArray <NSDictionary *> *historyDicts, NSError *error))completionHandler
{
	NSAssert(completionHandler != nil && self.isLoggedIn, @"completionHandler may not be nil");
	
	if (appID == nil)
	{
		completionHandler(nil, nil);
		return;
	}
	
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://appstoreconnect.apple.com/WebObjects/iTunesConnect.woa/ra/apps/%@/promocodes/history",appID]]];
	req.HTTPMethod = @"GET";
	[self _updateHeadersForRequest:req additionalFields:nil];
	req.HTTPShouldHandleCookies = YES;
	
	NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
																 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
																	 dispatch_async(dispatch_get_main_queue(), ^{
																		 if (data == nil || response == nil || error != nil)
																		 {
																			 completionHandler(nil, error);
																			 return;
																		 }
																		 
																		 NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
																		 if (dict == nil || ![dict isKindOfClass:[NSDictionary class]])
																		 {
																			 completionHandler(nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_PROMOCODES code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]);
																			 return;
																		 }
																		 
																		 NSDictionary *dataDict = dict[@"data"];
																		 if (data == nil)
																		 {
																			 completionHandler(nil, [NSError errorWithDomain:ESS_ERRORDOMAIN_APPSTORECONNECTAPI_PROMOCODES code:ESSASCAPIErrorCodeUnexpectedReply userInfo:nil]);
																			 return;
																		 }
																		 
																		 NSArray *codeDicts = dataDict[@"requests"];
																		 
																		 completionHandler(codeDicts, nil);
																	 });
																 }];
	[task resume];
}

@end


