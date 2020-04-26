//
//  Person.h
//  template
//
//  Created by du on 2020/4/24.
//  Copyright © 2020 du. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Person : NSObject<NSCopying>

+ (instancetype)personWithName:(NSString *)name;

@property (nonatomic,copy) NSString *desc;

@end

NS_ASSUME_NONNULL_END
