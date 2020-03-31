import XCTest
@testable import LFUCache

final class LFUCacheTests: XCTestCase {
    
    
    func testContentNodes() {
        
        let cache = LFUCache(countLimit: 10, duration: 1000)
        for i in 0...10 {
            cache.set(key: "\(i)", to: i)
        }
        
        XCTAssertNotNil(cache.arrContent.lastNode)
        var aNode = cache.arrContent.lastNode
        var index = 1
        while aNode != nil, index <= 9 {
            XCTAssertEqual(aNode!.content as! Int, index)
            aNode = aNode?.prev
            index += 1
        }
    }
    
    func testContentNodesWithGet() {
        
        let maxCount = 5
        
        for getIndex in 1...maxCount {
            let cache = LFUCache(countLimit: maxCount, duration: 1000)
            for i in 0...maxCount {
                cache.set(key: "\(i)", to: i)
            }
            _ = cache.get(key: "\(getIndex)", as: Int.self)
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
    
    
    
    func testCoutSpillOld() {
        
        let cache = LFUCache(countLimit: 10, duration: 1000)
        for i in 0...10 {
            cache.set(key: "\(i)", to: i)
        }
        // 0 被溢出
        XCTAssertNil(cache.get(key: "0", as: Int.self))
        XCTAssertEqual(cache.get(key: "1", as: Int.self)!, 1)
        // 因为 1 加了次数，所以这个 set 导致 2 溢出
        cache.set(key: "11", to: 11)
        XCTAssertNil(cache.get(key: "2", as: Int.self))
    }
    
    func testCoutSpillLessUsed() {
        
        let cache = LFUCache(countLimit: 10, duration: 1000)
        for i in 0...10 {
            let key = "\(i)"
            for _ in 0...i {
                _ = cache.get(key: key, as: Int.self)
            }
            cache.set(key: key, to: i)
        }
        // 10 被使用了 11 次，1 被使用了两次，0 被使用一次
        // 再添加 0 将无法添加进，读取一次之后再添加，会将 1 挤出
        cache.set(key: "0", to: 0)
        XCTAssertNil(cache.get(key: "0", as: Int.self))
        cache.set(key: "0", to: 0)
        XCTAssertNotNil(cache.get(key: "0", as: Int.self))
        XCTAssertNil(cache.get(key: "1", as: Int.self))
    }
    
    func testExpiredSpill() {
        
        let cache = LFUCache(countLimit: 10, duration: 2)
        for i in 0...4 {
            sleep(1)
            cache.set(key: "\(i)", to: i)
        }
        
        // 已经睡了 5 秒，0、1 应该已经过期了，2 刚刚过期，3、4 肯定未过期
        XCTAssertNil(cache.get(key: "0", as: Int.self))
        XCTAssertNil(cache.get(key: "1", as: Int.self))
        XCTAssertNil(cache.get(key: "2", as: Int.self))
        XCTAssertNotNil(cache.get(key: "3", as: Int.self))
        XCTAssertNotNil(cache.get(key: "4", as: Int.self))
    }
    
    
    func testDeleteLessUsedAndComeBack() {
        
        let cache = LFUCache(countLimit: 5, duration: 1000)
        for i in 0...5 {
            let key = "\(i)"
            for _ in 0...i {
                _ = cache.get(key: key, as: Int.self)
            }
            cache.set(key: key, to: i)
        }
        
        /// 最少使用的是 0 ，但是已经被自动删除，所以使用 1，被使用 2 次
        let deleteKey = "1"
        XCTAssertEqual(cache.arrContent.lastNode?.key, deleteKey)
        cache.delete(key: deleteKey)
        XCTAssertEqual(cache.arrContent.lastNode?.key, "2")
        XCTAssertNil(cache.get(key: deleteKey, as: Int.self))
        cache.set(key: deleteKey, to: 1)
        XCTAssertNotNil(cache.get(key: deleteKey, as: Int.self))
    }

    func testDeleteMiddleUsedAndComeBack() {
        
        let cache = LFUCache(countLimit: 5, duration: 1000)
        for i in 0...5 {
            let key = "\(i)"
            for _ in 0...i {
                _ = cache.get(key: key, as: Int.self)
            }
            cache.set(key: key, to: i)
        }
        
        /// 最少使用的是 0 ，但是已经被自动删除，所以使用 1，被使用 2 次
        let deleteKey = "3"
        cache.delete(key: deleteKey)
        XCTAssertNil(cache.get(key: deleteKey, as: Int.self))
        cache.set(key: deleteKey, to: 3)
        XCTAssertNotNil(cache.get(key: deleteKey, as: Int.self))
        
    }
    
    func testDeleteFrequencyUsedAndComeBack() {
        
        let cache = LFUCache(countLimit: 5, duration: 1000)
        for i in 0...5 {
            let key = "\(i)"
            for _ in 0...i {
                _ = cache.get(key: key, as: Int.self)
            }
            cache.set(key: key, to: i)
        }
        
        /// 最少使用的是 0 ，但是已经被自动删除，所以使用 1，被使用 2 次
        let deleteKey = "5"
        cache.delete(key: deleteKey)
        XCTAssertNil(cache.get(key: deleteKey, as: Int.self))
        cache.set(key: deleteKey, to: 5)
        XCTAssertNotNil(cache.get(key: deleteKey, as: Int.self))
        XCTAssertNotNil(cache.dicContent[deleteKey])
        XCTAssertNil(cache.dicContent[deleteKey]?.prev)
        
    }
    
    func testSetex() {
        
        let cache = LFUCache(countLimit: 5, duration: 1000)
        
        let key = "1"
        let timeout = 2
        cache.setex(key: key, to: 1, in: timeout)
        XCTAssertNotNil(cache.get(key: key, as: Int.self))
        sleep(UInt32(timeout))
        XCTAssertNil(cache.get(key: key, as: Int.self))
        XCTAssertNil(cache.dicContent[key])
    }
    
    static var allTests = [
        ("testContentNodes", testContentNodes),
    ]
}
