import XCTest
import NIO
@testable import LFUCache

@available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
extension EventLoop {
    func allCompleted() async throws {
        try await self.submit{()}.get()
    }
}

@available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
final class LFUCacheTests: XCTestCase {
    
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
    
    func testContentNodesWithGet() throws {
        
        let maxCount = 5
        
        for getIndex in 1...maxCount {
            let cache = LFUCache(loop: self.loop, countLimit: maxCount, duration: 1000)
            for i in 0...maxCount {
                cache.set(key: "\(i)", to: i)
            }
            _ = try cache.get(key: "\(getIndex)", as: Int.self).wait()
            XCTAssertNotNil(cache.arrContent.lastNode)
            var index = 1
            var aNode = cache.arrContent.lastNode
            while aNode != nil, index < maxCount {
                if index < getIndex {
                    XCTAssertEqual(aNode!.content as! Int, index)
                } else {
                    XCTAssertEqual(aNode!.content as! Int, index + 1)
                }
                aNode = aNode?.prev
                index += 1
            }
            XCTAssertEqual(aNode!.content as! Int, getIndex)
        }
    }
    
    
    
    func testCoutSpillOld() throws {
        
        let cache = LFUCache(loop: self.loop, countLimit: 10, duration: 1000)
        for i in 0...10 {
            cache.set(key: "\(i)", to: i)
        }
        // 0 被溢出
        XCTAssertNil(try cache.get(key: "0", as: Int.self).wait())
        XCTAssertEqual(try cache.get(key: "1", as: Int.self).wait(), 1)
        // 因为 1 加了次数，所以这个 set 导致 2 溢出
        cache.set(key: "11", to: 11)
        XCTAssertNil(try cache.get(key: "2", as: Int.self).wait())
    }
    
    func testCoutSpillLessUsed() throws {
        
        let cache = LFUCache(loop: self.loop, countLimit: 10, duration: 1000)
        for i in 0...10 {
            let key = "\(i)"
            for _ in 0...i {
                _ = try cache.get(key: key, as: Int.self).wait()
            }
            cache.set(key: key, to: i)
        }
        // 10 被使用了 11 次，1 被使用了两次，0 被使用一次
        // 再添加 0 将无法添加进，读取一次之后再添加，会将 1 挤出
        cache.set(key: "0", to: 0)
        XCTAssertNil(try cache.get(key: "0", as: Int.self).wait())
        cache.set(key: "0", to: 0)
        XCTAssertNotNil(try cache.get(key: "0", as: Int.self).wait())
        XCTAssertNil(try cache.get(key: "1", as: Int.self).wait())
    }
    
    func testExpiredSpill() throws {
        
        let cache = LFUCache(loop: self.loop, countLimit: 10, duration: 2)
        for i in 0...4 {
            sleep(1)
            cache.set(key: "\(i)", to: i)
        }
        
        // 已经睡了 5 秒，0、1 应该已经过期了，2 刚刚过期，3、4 肯定未过期
        XCTAssertNil(try cache.get(key: "0", as: Int.self).wait())
        XCTAssertNil(try cache.get(key: "1", as: Int.self).wait())
        XCTAssertNil(try cache.get(key: "2", as: Int.self).wait())
        XCTAssertNotNil(try cache.get(key: "3", as: Int.self).wait())
        XCTAssertNotNil(try cache.get(key: "4", as: Int.self).wait())
    }
    
    
    func testDeleteLessUsedAndComeBack() throws {
        
        let cache = LFUCache(loop: self.loop, countLimit: 5, duration: 1000)
        for i in 0...5 {
            let key = "\(i)"
            for _ in 0...i {
                _ = try cache.get(key: key, as: Int.self).wait()
            }
            cache.set(key: key, to: i)
        }
        
        /// 最少使用的是 0 ，但是已经被自动删除，所以使用 1，被使用 2 次
        let deleteKey = "1"
        cache.loop.execute {
             XCTAssertEqual(cache.arrContent.lastNode?.key, deleteKey)
        }
        cache.delete(key: deleteKey)
        cache.loop.execute {
            XCTAssertEqual(cache.arrContent.lastNode?.key, "2")
        }
        XCTAssertNil(try cache.get(key: deleteKey, as: Int.self).wait())
        cache.set(key: deleteKey, to: 1)
        XCTAssertNotNil(try cache.get(key: deleteKey, as: Int.self).wait())
    }

    func testDeleteMiddleUsedAndComeBack() throws {
        
        let cache = LFUCache(loop: self.loop, countLimit: 5, duration: 1000)
        for i in 0...5 {
            let key = "\(i)"
            for _ in 0...i {
                _ = try cache.get(key: key, as: Int.self).wait()
            }
            cache.set(key: key, to: i)
        }
        
        /// 最少使用的是 0 ，但是已经被自动删除，所以使用 1，被使用 2 次
        let deleteKey = "3"
        cache.delete(key: deleteKey)
        XCTAssertNil(try cache.get(key: deleteKey, as: Int.self).wait())
        cache.set(key: deleteKey, to: 3)
        XCTAssertNotNil(try cache.get(key: deleteKey, as: Int.self).wait())
        
    }
    
    func testDeleteFrequencyUsedAndComeBack() throws {
        
        let cache = LFUCache(loop: self.loop, countLimit: 5, duration: 1000)
        for i in 0...5 {
            let key = "\(i)"
            for _ in 0...i {
                _ = try cache.get(key: key, as: Int.self).wait()
            }
            cache.set(key: key, to: i)
        }
        
        /// 最少使用的是 0 ，但是已经被自动删除，所以使用 1，被使用 2 次
        let deleteKey = "5"
        cache.delete(key: deleteKey)
        XCTAssertNil(try cache.get(key: deleteKey, as: Int.self).wait())
        cache.set(key: deleteKey, to: 5)
        XCTAssertNotNil(try cache.get(key: deleteKey, as: Int.self).wait())
        XCTAssertNotNil(cache.dicContent[deleteKey])
        XCTAssertNil(cache.dicContent[deleteKey]?.prev)
        
    }
    
    func testSetex() throws {
        
        let cache = LFUCache(loop: self.loop, countLimit: 5, duration: 1000)
        
        let key = "1"
        let timeout = 2
        cache.setex(key: key, to: 1, in: timeout)
        XCTAssertNotNil(try cache.get(key: key, as: Int.self).wait())
        sleep(UInt32(timeout))
        XCTAssertNil(try cache.get(key: key, as: Int.self).wait())
        cache.loop.execute {
             XCTAssertNil(cache.dicContent[key])
        }
    }
    
    func testGetAsync() async throws {
        
        let cache = LFUCache(loop: self.loop, countLimit: 5, duration: 1000)
        
        let key = "key";
        let value = 1;
        cache.set(key: key, to: value);
        
        let result = await cache.get(key: key, as: type(of: value));
        
        XCTAssertEqual(result, value);
    }
    
    static var allTests = [
        ("testContentNodes", testContentNodes),
    ]
}
