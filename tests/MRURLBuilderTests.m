//
//  MRURLBuilderTests.m
//  Marquee tests
//

#import <Foundation/Foundation.h>
#import "MRTestSupport.h"
#import "MRConfig.h"
#import "MRURLBuilder.h"

void MRRunURLBuilderTests(void) {
    NSString *expectedAPI = [NSString stringWithFormat:
        @"https://api.simkl.com/sync/activities?client_id=%@&app-name=marquee&app-version=1.0",
        MR_SIMKL_CLIENT_ID];
    NSString *api = [MRURLBuilder apiURLForPath:@"sync/activities" query:nil];
    MRAssertEqualObjects(api, expectedAPI, @"api url");

    NSString *search = [MRURLBuilder searchURLWithQuery:@"Dune: Part Two & More" page:2];
    MRAssertTrue([search rangeOfString:@"q=Dune%3A%20Part%20Two%20%26%20More"].location != NSNotFound,
                 @"search encoding");
    MRAssertTrue([search rangeOfString:@"page=2"].location != NSNotFound, @"search page");

    NSString *expectedSearch = [NSString stringWithFormat:
        @"https://api.simkl.com/search/all?client_id=%@&app-name=marquee&app-version=1.0"
        @"&extended=full&limit=30&page=2&q=Dune%%3A%%20Part%%20Two%%20%%26%%20More",
        MR_SIMKL_CLIENT_ID];
    MRAssertEqualObjects(search, expectedSearch, @"search url");

    NSString *poster = [MRURLBuilder posterURLForPath:@"abc" size:@"_m"];
    MRAssertEqualObjects(poster,
        @"https://wsrv.nl/?url=https://simkl.in/posters/abc_m.webp&output=jpg&q=90",
        @"poster jpeg url");

    NSString *fanart = [MRURLBuilder fanartURLForPath:@"def" size:@"_medium"];
    MRAssertEqualObjects(fanart,
        @"https://wsrv.nl/?url=https://simkl.in/fanart/def_medium.webp&output=jpg&q=90",
        @"fanart jpeg url");

    NSString *web = [MRURLBuilder simklWebURLForType:MRMediaTypeMovie simklID:342994 slug:@"john-wick"];
    MRAssertEqualObjects(web, @"https://simkl.com/movies/342994/john-wick", @"simkl web url");

    NSString *expectedData = [NSString stringWithFormat:
        @"https://data.simkl.in/discover/trending/week_100.json"
        @"?client_id=%@&app-name=marquee&app-version=1.0&limit=30&type=a%%20b",
        MR_SIMKL_CLIENT_ID];
    NSString *data = [MRURLBuilder dataURLForPath:@"/discover/trending/week_100.json"
                                            query:@{@"type": @"a b", @"limit": @30}];
    MRAssertEqualObjects(data, expectedData, @"data url and sorted query");

    NSString *encoded = [MRURLBuilder apiURLForPath:@"search/all"
                                              query:@{@"q": @"a+b/c?d=e&f~g-h_i.j"}];
    MRAssertTrue([encoded rangeOfString:@"q=a%2Bb%2Fc%3Fd%3De%26f~g-h_i.j"].location != NSNotFound,
                 @"strict percent encoding");

    NSString *placeholder = [MRURLBuilder posterPlaceholderURL];
    MRAssertEqualObjects(placeholder,
        @"https://wsrv.nl/?url=https://simkl.in/posters/poster_no_pic_c.png&output=jpg&q=90",
        @"placeholder jpeg url");

    NSString *avatar = [MRURLBuilder avatarURLForPath:@"1/user_100.jpg"];
    MRAssertEqualObjects(avatar, @"https://simkl.in/avatars/1/user_100.jpg",
                         @"avatar path url");
    NSString *fullAvatar = [MRURLBuilder avatarURLForPath:@"https://simkl.in/avatars/1/user_100.jpg"];
    MRAssertEqualObjects(fullAvatar, @"https://simkl.in/avatars/1/user_100.jpg",
                         @"avatar full url");

    MRAssertEqualObjects([MRURLBuilder simklWebURLForType:MRMediaTypeShow simklID:123 slug:@"the-bear"],
                         @"https://simkl.com/tv/123/the-bear", @"simkl tv url");
    MRAssertEqualObjects([MRURLBuilder simklWebURLForType:MRMediaTypeAnime simklID:456 slug:@"frieren"],
                         @"https://simkl.com/anime/456/frieren", @"simkl anime url");
    MRAssertEqualObjects([MRURLBuilder simklWebURLForType:MRMediaTypeMovie simklID:7 slug:nil],
                         @"https://simkl.com/movies/7", @"simkl url without slug");
}
