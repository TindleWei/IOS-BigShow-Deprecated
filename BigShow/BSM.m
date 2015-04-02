//
//  BSM.m
//  BigShow
//
//  Created by tindle on 15/4/2.
//  Copyright (c) 2015年 tindle. All rights reserved.
//

#import "BSM.h"
#import <AVOSCloudSNS/AVUser+SNS.h>
#import <AVOSCloud/AVJSONRequestOperation.h>

BOOL is7orLater(){
    static int sysVersion =0;
    if (sysVersion==0) {
        sysVersion=[[[[UIDevice currentDevice] systemVersion] substringToIndex:1] integerValue];
    }
    return sysVersion>7;
}

@implementation BSTheme
+(void)changeTheme:(BSThemeType)theme{
    model.theme=theme;
    [[NSUserDefaults standardUserDefaults] setInteger:theme forKey:@"Theme"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
+(UIColor *)textColor{
    switch(model.theme){
        case BSThemeTypeLight:
            return [UIColor lightTextColor];
        case BSThemeTypeModern:
            return [UIColor whiteColor];
    }
    return nil;
}
+(UIColor *)bgColor{
    switch(model.theme){
        case BSThemeTypeLight:
            return [UIColor lightTextColor];
        case BSThemeTypeModern:
            return [UIColor clearColor];
    }
    return nil;
}
+(UIImage*)bgImage{
    switch(model.theme){
        case BSThemeTypeLight:
            return [UIImage imageNamed:@"bg"];
        case BSThemeTypeModern:
            return [UIImage imageNamed:@"bg2"];
    }
    return nil;
}
@end

@implementation BSM
+(BSM*)shared{
#ifdef DEBUG
    //允许打印AVCloud日志
    setenv("LOG_CURL", "YES", 0);
#endif
    static BSM *_bsm_=Nil;
    if (_bsm_==Nil) {
        _bsm_=[BSM new];
    }
    return _bsm_;
}

+(NSString*)storeIdOfURL:(NSString *)url{
    if ([url rangeOfString:@"itunes.apple.com"].length) {
        NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"id([0-9]{8,})" options:0 error:nil];
        NSTextCheckingResult *result= [re firstMatchInString:url options:NSMatchingReportCompletion range:NSMakeRange(0, url.length)];
        
        if (result) {
            NSString *storeId=[url substringWithRange:[result rangeAtIndex:1]];
            return storeId;
        }
    }
    
    return nil;
}

//登录方法
-(void)login:(AVUserResultBlock)callback{
    [AVOSCloudSNS setupPlatform:AVOSCloudSNSSinaWeibo withAppKey:@"718087462" andAppSecret:@"e8c9fa9fd28daa480a871c1ae0115565" andRedirectURI:@"http://vz.avosapps.com/oauth?type=weibo"];
    
    [AVOSCloudSNS loginWithCallback:^(NSDictionary* object, NSError *error){
        if (error==nil && object) {
            [BSUser loginWithAuthData:object block:^(AVUser *user, NSError *error){
                BOOL needSave=NO;
                if (![user objectForKey:@"avatar"]) {
                    [user setObject:object[@"avatar"] forKey:@"avatar"];
                    needSave=YES;
                }
                
                if (needSave) {
                    [user save];
                }
                
                AVInstallation *currentInstallation = [AVInstallation
                                                       currentInstallation];
                if (currentInstallation.deviceToken) {
                    [currentInstallation setObject:user forKey:@"user"];
                    [currentInstallation saveInBackground];
                }
                callback(user, error);
            }];
        }
    } toPlatform:AVOSCloudSNSSinaWeibo];
    
    [AVAnalytics event:@"用户登录"];
}

-(void)logout{
    [AVUser logOut];
    
    NSDictionary *dict= [AVOSCloudSNS userInfo:AVOSCloudSNSSinaWeibo];
    NSString *token=[dict objectForKey:@"access_token"];
    
    [model.client getPath:@"https://api.weibo.com/oauth2/revokeoauth2" parameters:@{@"access_token":token} success:^(AVHTTPRequestOperation *operation, id responseObject) {
        NSLog(@"success");
    } failure:^(AVHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"logout error %@",[error description]);
    }];
    
    [AVOSCloudSNS logout:AVOSCloudSNSSinaWeibo];
    
    AVInstallation *currentInstallation = [AVInstallation currentInstallation];
    if ([currentInstallation objectForKey:@"user"]) {
        [currentInstallation removeObjectForKey:@"user"];
        [currentInstallation saveInBackground];
    }
    
    [AVAnalytics event:@"用户注销"];
}

-(void)getCommentWithWbid:(NSString*)wbid callback:(AVArrayResultBlock)callback{
    if (![AVOSCloudSNS doesUserExpireOfPlatform:AVOSCloudSNSSinaWeibo]) {
        NSDictionary *dict= [AVOSCloudSNS userInfo:AVOSCloudSNSSinaWeibo];
        NSString *token=[dict objectForKey:@"access_token"];
        
        NSString *url=[NSString stringWithFormat:@"https://api.weibo.com/2/comments/show.json?id=%@&access_token=%@",wbid,token];
        NSURLRequest *req=[NSURLRequest requestWithURL:[NSURL URLWithString:url]];
        
        AVJSONRequestOperation *opt=[AVJSONRequestOperation JSONRequestOperationWithRequest:req success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
            NSArray *arr= JSON[@"comments"];
            if (arr) {
                NSArray *shuma=@[@"2043408047",@"1761596064",@"1882458640",@"1841288857",@"3787475667",@"3701452524"];
                
                NSMutableArray *a=[NSMutableArray array];
                
                for (NSDictionary *comment in arr) {
                    NSString *idstr=comment[@"user"][@"idstr"];
                    if ([shuma containsObject:idstr]) {
                        continue;
                    }
                    
                    [a addObject:comment];
                }
                
                [a sortUsingDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"idstr" ascending:YES]]];
                callback(a,nil);
            }else{
                callback(Nil,Nil);
            }
            
        } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
            callback(Nil,error);
            NSLog(@"%@", [error description]);
        }];
        
        [self.client enqueueHTTPRequestOperation:opt];
    }else{
        callback(nil,[NSError errorWithDomain:@"vz" code:1 userInfo:nil]);
    }
    
}


-(void)commentToWbid:(NSString*)wbid toCommentId:(NSString*)cid withText:(NSString*)text callback:(AVSNSResultBlock)callback{
    if (![AVOSCloudSNS doesUserExpireOfPlatform:AVOSCloudSNSSinaWeibo]) {
        NSDictionary *dict= [AVOSCloudSNS userInfo:AVOSCloudSNSSinaWeibo];
        NSString *token=[dict objectForKey:@"access_token"];
        
        NSString *url=[NSString stringWithFormat:@"https://api.weibo.com/2/comments/%@.json",cid?@"reply":@"create"];
        
        NSMutableDictionary *param=[NSMutableDictionary dictionary];
        [param setObject:token forKey:@"access_token"];
        [param setObject:wbid forKey:@"id"];
        [param setObject:text forKey:@"comment"];
        if (cid) {
            [param setObject:cid forKey:@"cid"];
        }
        NSURLRequest *req=[self.client requestWithMethod:@"POST" path:url parameters:param];
        
        AVJSONRequestOperation *opt=[AVJSONRequestOperation JSONRequestOperationWithRequest:req success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
            callback(JSON,nil);
            
        } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
            callback(JSON,error);
        }];
        
        [self.client enqueueHTTPRequestOperation:opt];
    }else{
        callback(nil,[NSError errorWithDomain:@"vz" code:1 userInfo:nil]);
    }
    
}

-(void)uploadImage:(UIImage*)image callback:(AVSNSResultBlock)callback{
    if (![AVOSCloudSNS doesUserExpireOfPlatform:AVOSCloudSNSSinaWeibo]) {
        NSDictionary *dict= [AVOSCloudSNS userInfo:AVOSCloudSNSSinaWeibo];
        NSString *token=[dict objectForKey:@"access_token"];
        
        NSString *url=[NSString stringWithFormat:@"https://api.weibo.com/2/statuses/upload_pic.json"];
        
        NSMutableDictionary *param=[NSMutableDictionary dictionary];
        [param setObject:token forKey:@"access_token"];
        [param setObject:UIImageJPEGRepresentation(image, 0.8) forKey:@"pic"];
        
        NSURLRequest *req=[self.client requestWithMethod:@"POST" path:url parameters:param];
        
        AVJSONRequestOperation *opt=[AVJSONRequestOperation JSONRequestOperationWithRequest:req success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
            callback(JSON,nil);
            
        } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
            callback(JSON,error);
        }];
        
        [self.client enqueueHTTPRequestOperation:opt];
    }else{
        callback(nil,[NSError errorWithDomain:@"vz" code:1 userInfo:nil]);
    }
}

@end

@implementation BSUser
@dynamic avatar;
+ (NSString *)parseClassName {
    return @"_User";
}

-(NSString*)wbid{
    NSString *uid=self[@"authData"][@"weibo"][@"uid"];
    
    return uid;
}

-(void)findMyFriendOnWeibo:(AVArrayResultBlock)callback{
    NSString *uid=[self wbid];
    
    if (uid && ![AVOSCloudSNS doesUserExpireOfPlatform:AVOSCloudSNSSinaWeibo]) {
        NSString *token=[[self objectForKey:@"authData"] valueForKeyPath:@"weibo.access_token"];
        
        NSString *url=[NSString stringWithFormat:@"https://api.weibo.com/2/friendships/friends/ids.json?uid=%@&access_token=%@",uid,token];
        NSURLRequest *req=[NSURLRequest requestWithURL:[NSURL URLWithString:url]];
        
        AVJSONRequestOperation *opt=[AVJSONRequestOperation JSONRequestOperationWithRequest:req success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
            NSArray *arr= JSON[@"ids"];
            if (arr) {
                AVQuery *q=[BSUser query];
                [q whereKey:@"authData.weibo.uid" containedIn:arr];
                
                [q findObjectsInBackgroundWithBlock:callback];
            }else{
                callback(Nil,Nil);
            }
            
        } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
            callback(Nil,error);
        }];
        
        [model.client enqueueHTTPRequestOperation:opt];
    }else{
        callback(Nil,[NSError errorWithDomain:@"vz" code:1 userInfo:nil]);
    }
}

//-(void)watch:(BOOL)flat post:(VZPost*)post callback:(AVBooleanResultBlock)callback{
//    if (flat) {
//        [post.watchUsers addObject:post];
//    }else{
//        [post.watchUsers removeObject:self];
//    }
//    
//    [post saveInBackgroundWithBlock:callback];
//}


@end
