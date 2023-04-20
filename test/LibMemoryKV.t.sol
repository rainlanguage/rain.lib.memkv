// SPDX-License-Identifier: CAL
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "sol.lib.memory/LibMemory.sol";

import "../src/LibMemoryKV.sol";
import "./LibMemoryKVSlow.sol";

contract LibMemoryKVTest is Test {
    function testSetReadVal(MemoryKVKey k_, MemoryKVVal v_) public {
        MemoryKV kv_ = MemoryKV.wrap(0);

        // Initially the key will return no pointer.
        MemoryKVPtr ptr0_ = LibMemoryKV.getPtr(kv_, k_);
        assertEq(0, MemoryKVPtr.unwrap(ptr0_));

        assertTrue(LibMemory.memoryIsAligned());
        Pointer alloc0_ = LibPointer.allocatedMemoryPointer();
        kv_ = LibMemoryKV.setVal(kv_, k_, v_);
        Pointer alloc1_ = LibPointer.allocatedMemoryPointer();
        assertTrue(Pointer.unwrap(alloc1_) == Pointer.unwrap(alloc0_) + 0x60);
        assertTrue(LibMemory.memoryIsAligned());

        assertTrue(MemoryKV.unwrap(kv_) > 0);

        MemoryKVPtr ptr1_ = LibMemoryKV.getPtr(kv_, k_);

        assertTrue(MemoryKVPtr.unwrap(ptr1_) > 0);

        assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(ptr1_)), MemoryKVVal.unwrap(v_));
    }

    function testSetReadVal2(MemoryKVKey k0_, MemoryKVVal v00_, MemoryKVVal v01_, MemoryKVKey k1_, MemoryKVVal v10_, MemoryKVVal v11_) public {
        vm.assume(MemoryKVKey.unwrap(k0_) != MemoryKVKey.unwrap(k1_));

        MemoryKV kv_ = MemoryKV.wrap(0);

        assertTrue(LibMemory.memoryIsAligned());
        kv_ = LibMemoryKV.setVal(kv_, k0_, v00_);
        assertTrue(LibMemory.memoryIsAligned());

        assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(LibMemoryKV.getPtr(kv_, k0_))), MemoryKVVal.unwrap(v00_));
        assertEq(MemoryKVPtr.unwrap(LibMemoryKV.getPtr(kv_, k1_)), 0);

        assertTrue(LibMemory.memoryIsAligned());
        kv_ = LibMemoryKV.setVal(kv_, k1_, v10_);
        assertTrue(LibMemory.memoryIsAligned());

        assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(LibMemoryKV.getPtr(kv_, k0_))), MemoryKVVal.unwrap(v00_));
        assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(LibMemoryKV.getPtr(kv_, k1_))), MemoryKVVal.unwrap(v10_));

        assertTrue(LibMemory.memoryIsAligned());
        kv_ = LibMemoryKV.setVal(kv_, k1_, v11_);
        assertTrue(LibMemory.memoryIsAligned());

        assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(LibMemoryKV.getPtr(kv_, k0_))), MemoryKVVal.unwrap(v00_));
        assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(LibMemoryKV.getPtr(kv_, k1_))), MemoryKVVal.unwrap(v11_));

        assertTrue(LibMemory.memoryIsAligned());
        kv_ = LibMemoryKV.setVal(kv_, k0_, v01_);
        assertTrue(LibMemory.memoryIsAligned());

        assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(LibMemoryKV.getPtr(kv_, k0_))), MemoryKVVal.unwrap(v01_));
        assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(LibMemoryKV.getPtr(kv_, k1_))), MemoryKVVal.unwrap(v11_));
    }

    function testReadPtrValGas() public {
        // This is an illegal read but it gives the cost without memory
        // expansion costs etc.
        LibMemoryKV.readPtrVal(MemoryKVPtr.wrap(0));
    }

    function testGetPtrGas() public {
        MemoryKV kv_ = MemoryKV.wrap(0);
        LibMemoryKV.getPtr(kv_, MemoryKVKey.wrap(0));
    }

    function testSetValGas0() public {
        MemoryKV kv_ = MemoryKV.wrap(0);
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
    }

    function testSetValGas1() public {
        MemoryKV kv_ = MemoryKV.wrap(0);
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
    }

    function testSetValGas3() public {
        MemoryKV kv_ = MemoryKV.wrap(0);
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
    }

    function testSetValGas4() public {
        MemoryKV kv_ = MemoryKV.wrap(0);
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(7), MemoryKVVal.wrap(8));
    }

    function testSetValGas5() public {
        MemoryKV kv_ = MemoryKV.wrap(0);
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(7), MemoryKVVal.wrap(8));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(9), MemoryKVVal.wrap(10));
    }

    function testRoundTrip(uint256[] memory kvs_) public {
        // We hit gas limits pretty easily in this test for "large" sets.
        vm.assume(kvs_.length < 50);
        vm.assume(kvs_.length % 2 == 0);

        MemoryKV kv_ = MemoryKV.wrap(0);

        uint256[] memory slowKVs_ = new uint256[](0);
        for (uint256 i_ = 0; i_ < kvs_.length; i_ += 2) {
            uint256 k_ = kvs_[i_];
            uint256 v_ = kvs_[i_ + 1];

            kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(k_), MemoryKVVal.wrap(v_));
            slowKVs_ = LibMemoryKVSlow.set(slowKVs_, k_, v_);
        }

        uint256[] memory roundKVs_ = LibMemoryKV.toUint256Array(kv_);
        assertEq(slowKVs_.length, roundKVs_.length);

        for (uint256 i_ = 0; i_ < slowKVs_.length; i_ += 2) {
            uint256 k_ = slowKVs_[i_];
            (bool slowExists_, uint256 slowVal_) = LibMemoryKVSlow.get(slowKVs_, k_);
            (bool roundExists_, uint256 roundVal_) = LibMemoryKVSlow.get(roundKVs_, k_);
            assertEq(slowExists_, true);
            assertEq(roundExists_, true);
            assertEq(slowVal_, roundVal_);
        }
    }
}
