//
//  LFUCacheTests.swift
//
//
//  Created by 黄磊 on 2022/3/20.
//


import Testing
import NIO
@testable import LFUCache

@CacheActor
@Suite
struct LFUCacheTests {
    
    @Test
    func testContentNodes() throws {
        
        let cache = LFUCache(countLimit: 10, duration: 1000)
        for i in 0...10 {
            cache.set(key: "\(i)", to: i)
        }
        
        _ = cache.get(key: "\(0)", as: Int.self)
        
        #expect(cache.arrContent.lastNode != nil)
        var aNode = cache.arrContent.lastNode
        var index = 1
        while aNode != nil, index <= 9 {
            #expect((aNode!.content as! Int) == index)
            aNode = aNode?.prev
            index += 1
        }
    }
    
    @Test
    func testContentNodesWithGet() throws {
        
        let maxCount = 5
        
        for getIndex in 1...maxCount {
            let cache = LFUCache(countLimit: maxCount, duration: 1000)
            for i in 0...maxCount {
                cache.set(key: "\(i)", to: i)
            }
            _ = cache.get(key: "\(getIndex)", as: Int.self)
            #expect(cache.arrContent.lastNode != nil)
            var index = 1
            var aNode = cache.arrContent.lastNode
            while aNode != nil, index < maxCount {
                if index < getIndex {
                    #expect((aNode!.content as! Int) == index)
                } else {
                    #expect((aNode!.content as! Int) == index + 1)
                }
                aNode = aNode?.prev
                index += 1
            }
            #expect((aNode!.content as! Int) == getIndex)
        }
    }
    
    
    @Test
    func testCoutSpillOld() throws {
        
        let cache = LFUCache(countLimit: 10, duration: 1000)
        for i in 0...10 {
            cache.set(key: "\(i)", to: i)
        }
        // 0 被溢出
        #expect(cache.get(key: "0", as: Int.self) == nil)
        #expect(cache.get(key: "1", as: Int.self) == 1)
        // 因为 1 加了次数，所以这个 set 导致 2 溢出
        cache.set(key: "11", to: 11)
        #expect(cache.get(key: "2", as: Int.self) == nil)
    }
    
    @Test
    func testCoutSpillLessUsed() throws {
        
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
        #expect(cache.get(key: "0", as: Int.self) == nil)
        cache.set(key: "0", to: 0)
        #expect(cache.get(key: "0", as: Int.self) != nil)
        #expect(cache.get(key: "1", as: Int.self) == nil)
    }
    
    @Test
    func testExpiredSpill() throws {
        
        let cache = LFUCache(countLimit: 10, duration: 2)
        for i in 0...4 {
            sleep(1)
            cache.set(key: "\(i)", to: i)
        }
        
        // 已经睡了 5 秒，0、1 应该已经过期了，2 刚刚过期，3、4 肯定未过期
        #expect(cache.get(key: "0", as: Int.self) == nil)
        #expect(cache.get(key: "1", as: Int.self) == nil)
        #expect(cache.get(key: "2", as: Int.self) == nil)
        #expect(cache.get(key: "3", as: Int.self) != nil)
        #expect(cache.get(key: "4", as: Int.self) != nil)
    }
    
    @Test
    func testDeleteLessUsedAndComeBack() throws {
        
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

        #expect(cache.arrContent.lastNode?.key == deleteKey)

        cache.delete(key: deleteKey)

        #expect(cache.arrContent.lastNode?.key == "2")

        #expect(cache.get(key: deleteKey, as: Int.self) == nil)
        cache.set(key: deleteKey, to: 1)
        #expect(cache.get(key: deleteKey, as: Int.self) != nil)
    }

    @Test
    func testDeleteMiddleUsedAndComeBack() throws {
        
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
        #expect(cache.get(key: deleteKey, as: Int.self) == nil)
        cache.set(key: deleteKey, to: 3)
        #expect(cache.get(key: deleteKey, as: Int.self) != nil)
        
    }
    
    @Test
    func testDeleteFrequencyUsedAndComeBack() throws {
        
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
        #expect(cache.get(key: deleteKey, as: Int.self) == nil)
        cache.set(key: deleteKey, to: 5)
        #expect(cache.get(key: deleteKey, as: Int.self) != nil)
        #expect(cache.dicContent[deleteKey] != nil)
        #expect(cache.dicContent[deleteKey]?.prev == nil)
    }
    
    @Test
    func testSetex() throws {
        
        let cache = LFUCache(countLimit: 5, duration: 1000)
        
        let key = "1"
        let timeout = 2
        cache.setex(key: key, to: 1, in: timeout)
        #expect(cache.get(key: key, as: Int.self) != nil)
        sleep(UInt32(timeout))
        #expect(cache.get(key: key, as: Int.self) == nil)

        #expect(cache.dicContent[key] == nil)
    }
    
    @Test
    func testGetAsync() throws {
        
        let cache = LFUCache(countLimit: 5, duration: 1000)
        
        let key = "key";
        let value = 1;
        cache.set(key: key, to: value);
        
        let result = cache.get(key: key, as: type(of: value));
        
        #expect(result == value);
    }
}
