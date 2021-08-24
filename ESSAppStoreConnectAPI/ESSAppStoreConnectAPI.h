//
//  ESSAppStoreConnectAPI.h
//  PromoCodes
//
//  Created by Matthias Gansrigler on 12.02.2019.
//  Copyright © 2019 Eternal Storms Software. All rights reserved.
//

/*
  MIT License
  
  Copyright (c) 2019-present Matthias Gansrigler (Eternal Storms Software, https://eternalstorms.at)
  
  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:
  
  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.
  
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
  */

 /*
  API calls pieced together from fastlane ( https://github.com/fastlane/fastlane )
  
  The MIT License (MIT)
  
  Copyright (c) 2015-present the fastlane authors
  
  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:
  
  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.
  
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
  */

#import "TargetConditionals.h"

#if TARGET_OS_OSX
#import <Foundation/Foundation.h>
#else
#import <UIKit/UIKit.h>
#endif

typedef enum : NSUInteger {
	ESSASCAPIErrorCodeMalformedRequest 			= 1,
	ESSASCAPIErrorCodeServiceKeyMissing			= 2,
	ESSASCAPIErrorCodeUnexpectedReply 			= 3,
	ESSASCAPIErrorCodeSecurityCodeLocked		= 4,
	ESSASCAPIErrorCodeTooManyCodesSent 			= 5,
	ESSASCAPIErrorCodeTooManyCodesValidated		= 6,
	ESSASCAPIErrorCodeNotLoggedIn				= 7
} ESSASCAPIErrorCode;

#define ESS_ERRORDOMAIN_APPSTORECONNECTAPI_LOGIN			@"at.EternalStorms.PromoCodes.AppStoreConnectLogin"
#define ESS_ERRORDOMAIN_APPSTORECONNECTAPI_APPS				@"at.EternalStorms.PromoCodes.AppStoreConnectApps"
#define ESS_ERRORDOMAIN_APPSTORECONNECTAPI_PROMOCODES		@"at.EternalStorms.PromoCodes.AppStoreConnectPromoCodes"


/*!
 @interface 	ESSAppStoreConnectAPI
 @abstract		A singleton class to communicate with App Store Connect to request promo codes. This code was pieced together from https://github.com/fastlane/fastlane .
 @discussion	Begin with @c -loginWithUsername:password:completionHandler:. From there, if @c completionHandler's @c loggedIn == YES, you're able to use "teams" from the 'info' dictionary right away with @c -appsForTeamWithProviderID:completionHandler:. If @c loggedIn == NO and @c needsTwoFactorAuth == YES, you need to finish 2FA first (see @c -loginWithUsername:password:completionHandler:'s discussion).
 */
@interface ESSAppStoreConnectAPI : NSObject

+ (instancetype)sharedAPI;

#pragma mark - Login

/*!
 @method		loginWithUsername:password:completionHandler:
 @abstract		Starts the login process with App Store Connect
 @param			username The username / Apple ID of the user
 @param			password The password for @c username.
 @param			completionHandler The completionHandler, called on the main thread. @c loggedIn is YES if login worked right away, NO if there are further steps or an error involved. @c needsTwoFactorAuth is YES if there are further login steps involved, NO if login works right away or there was an error. @c info contains further information, depending on @c loggedIn and @c needsTwoFactorAuth.
 @discussion	@c info contains the following keys if @c loggedIn is YES: "teams" (array of dictionaries), "teamID" (number or string, the currently selected team) and "apps" (an array of dictionaries). If @c loggedIn is NO and @c needsTwoFactorAuth is YES, the info dictionary contains the following keys: "securityCode" (a dictionary containing code info), "phoneNumbers" (an array of dictionaries describing the trusted phone numbers), "didSendCode" (whether an auth code was already sent or not), "wasTrustedDeviceCode" (whether the code was sent via push to a trusted device or SMS to a trusted phone number), "scnt" and "AppleIDSessionID" (two Apple-specific, opaque strings)
 */
- (void)loginWithUsername:(NSString *)username
				 password:(NSString *)password
		completionHandler:(void (^)(BOOL loggedIn, BOOL needsTwoFactorAuth, NSDictionary *info, NSError *error))completionHandler;

/*!
 @method		resend2FACodeWithInfo:completionHandler:
 @abstract		Used to request an SMS containing a new 2FA code to the specified phone number.
 @param			phoneID The phone number ID to send the new 2FA code to. May not be nil.
 @param			completionHandler Called on the main thread, @c resent is set to YES if the resend request was successful, otherwise NO.
 */
- (void)resend2FACodeWithPhoneID:(NSNumber *)phoneID
			   completionHandler:(void (^)(BOOL resent, NSError *err))completionHandler;

/*!
 @method		finish2FAWithCode:phoneID:completionHandler:
 @abstract		Used to finish logging in using the code we received and the optional phoneID if the code was sent to a phone number via SMS.
 @param			code The code the user received via SMS or push and entered into the app
 @param			phoneID If this was an SMS, we need the according phoneID. Otherwise nil.
 @param			completionHandler Called on the main thread, this returns @c loggedIn YES if login was successful (and the @c info dictionary will contain the keys "teams", "teamID" and "apps"), or NO and nil if an error occurred.
 */
- (void)finish2FAWithCode:(NSString *)code
				  phoneID:(NSNumber *)phoneID
		completionHandler:(void (^)(BOOL loggedIn, NSDictionary *info, NSError *error))completionHandler;

/*!
 @method		checkLoginWithCompletionHandler:
 @abstract		Used to see if the cookies and session from a previous login are still valid.
 @param			completionHandler Called on the main thread.
 */
- (void)checkLoginWithCompletionHandler:(void (^)(BOOL loggedIn, NSArray <NSDictionary *> *teams, NSNumber *currentTeamID, NSArray <NSDictionary *> *apps, NSError *error))completionHandler;

#pragma mark - App Retrieval

/*!
 @method		appsForTeamWithProviderID:completionHandler:
 @abstract		Loads the apps for the team specified with @c providerID.
 @discussion	Must be logged in with a user using @c -loginWithUsername:password:completionHandler must have been called before using this.
 @param			providerID The team's ID to load apps for. Internally retrieved with the session data.
 @param			completionHandler Called on the main thread, returns an array containing dictionaries describing the apps available. A dictionary contains these keys: "id" (the app's adamId), "name" (the app's name), "bundleID" (the app's bundle ID), "sku" (the vendorId), "platform" (osx, ios or appletvos)
 */
- (void)appsForTeamWithProviderID:(NSNumber *)providerID
				completionHandler:(void (^)(NSArray *apps, NSError *error))completionHandler;

#pragma mark - Promo Code Info and Creation

/*!
 @method		promoCodeInforForAppWithID:completionHandler:
 @abstract		Loads information about the app and the availability of promo codes.
 @discussion	Must be logged in with a user using @c -loginWithUsername:password:completionHandler must have been called before using this.
 @param			appID The app to load the info for. Retrieved in @c -appsForTeamWithProviderID:completionHandler:. May not be nil.
 @param			completionHandler Called on the main thread, upon success the @c info dictionary contains the following keys: "version" (the version string of the app), "versionID" (the version id), "contractFilename" (a relative path to the contract file on Apple's servers), "codesLeft" (the amount of promo codes left to be requested)
 */
- (void)promoCodeInfoForAppWithID:(NSString *)appID
				completionHandler:(void(^)(NSDictionary *info, NSError *error))completionHandler;

/*!
 @method		requestPromoCodesForAppWithID:versionID:quantity:contractFileName:completionHandler:
 @abstract		Requests the specified amount (@c quantity) of promo codes for the app specified via @c appID and @c versionID.
 @discussion	Must be logged in with a user using @c -loginWithUsername:password:completionHandler must have been called before using this.
 @param			appID Represents the app for which to request the promo codes for. Retrieved in @c -appSForTeamWithProviderID:completionHandler:
 @param			versionID Represents the current version of the app. Retrieved in @c -promoCodeInforForAppWithID:completionHandler:
 @param			contractFilename Currently unused.
 @param			completionHandler Called on the main thread. Upon success, promoCodes contains an array of dictionaries, which contains the following keys: "code" (the promo code), "creationDate" (the date this code was created by Apple), "expirationDate" (the date this code will expire), "requestId" (currently unused), "platform" (the platform of the app - osx, ios or appletvos), "version" (the version string)
 */
- (void)requestPromoCodesForAppWithID:(NSString *)appID
							versionID:(NSString *)versionID
							 quantity:(NSUInteger)quantity
					 contractFileName:(NSString *)contractFilename
					completionHandler:(void (^)(NSArray <NSDictionary *> *promoCodes, NSError *error))completionHandler;

@end


