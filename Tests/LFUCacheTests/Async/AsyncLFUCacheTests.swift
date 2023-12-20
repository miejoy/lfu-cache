//
//  AsyncLFUCacheTests.swift
//  
//
//  Created by 黄磊 on 2022/3/20.
//

import XCTest
import NIO
@testable import LFUCache


extension EventLoop {
    func allCompleted() async throws {
        try await self.submit{()}.get()
    }
}

final class AsyncLFUCacheTests: XCTestCase {
    
    var loop : EventLoop {
        
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        return group.next()
    }
    
    func testContentNodes() async throws {
        
        let cache = LFUCache(loop: self.loop, countLimit: 10, duration: 1000)
        for i in 0...10 {
            cache.set(key: "\(i)", to: i)
        }
        
        try await self.loop.allCompleted()
        
        XCTAssertNotNil(cache.arrContent.lastNode)
        var aNode = cache.arrContent.lastNode
        var index = 1
        while aNode != nil, index <= 9 {
            XCTAssertEqual(aNode!.content as! Int, index)
            aNode = aNode?.prev
            index += 1
        }
    }
    
    func testGetAsync() async throws {
        
        let cache = LFUCache(loop: self.loop, countLimit: 5, duration: 1000)
        
        let key = "key";
        let value = 1;
        cache.set(key: key, to: value);
        
        let result = try await cache.get(key: key, as: type(of: value));
        
        XCTAssertEqual(result, value);
    }
    
    static var allTests = [
        ("testContentNodes", testContentNodes),
    ]
}
