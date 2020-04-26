//
//  Person.m
//  template
//
//  Created by du on 2020/4/24.
//  Copyright © 2020 du. All rights reserved.
//

#import "Person.h"

@implementation Person


+ (instancetype)personWithName:(NSString *)name{
    Person *p = [[Person alloc]init];
    p.desc = name;
    return p;
}

- (id)copyWithZone:(NSZone *)zone{
    Person *p = [[Person alloc]init];
    p.desc = self.desc;
    return p;
}

- (void)dealloc{
    NSLog(@"Person:%@ dealloc",self.desc);
}



@end
