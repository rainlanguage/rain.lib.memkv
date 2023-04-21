// SPDX-License-Identifier: CAL
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "sol.lib.memory/LibMemory.sol";

import "../src/LibMemoryKV.sol";
import "./LibMemoryKVSlow.sol";

contract LibMemoryKVTest is Test {
    function testSetReadVal0(MemoryKVKey k_, MemoryKVVal v_) public {
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

    function testSetReadSimple0() public {
        MemoryKV kv_ = MemoryKV.wrap(0);
        MemoryKVKey k0_ = MemoryKVKey.wrap(1);
        MemoryKVVal v0_ = MemoryKVVal.wrap(2);
        kv_ = LibMemoryKV.setVal(kv_, k0_, v0_);
        MemoryKVPtr ptr0_ = LibMemoryKV.getPtr(kv_, k0_);
        assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(ptr0_)), MemoryKVVal.unwrap(v0_));

        MemoryKVKey k1_ = MemoryKVKey.wrap(3);
        MemoryKVVal v1_ = MemoryKVVal.wrap(4);
        kv_ = LibMemoryKV.setVal(kv_, k1_, v1_);
        MemoryKVPtr ptr1_ = LibMemoryKV.getPtr(kv_, k1_);
        assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(ptr1_)), MemoryKVVal.unwrap(v1_));

        MemoryKVVal v2_ = MemoryKVVal.wrap(5);
        kv_ = LibMemoryKV.setVal(kv_, k0_, v2_);
        MemoryKVPtr ptr2_ = LibMemoryKV.getPtr(kv_, k0_);
        assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(ptr2_)), MemoryKVVal.unwrap(v2_));
        MemoryKVPtr ptr3_ = LibMemoryKV.getPtr(kv_, k1_);
        assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(ptr3_)), MemoryKVVal.unwrap(v1_));
    }

    function testSetReadSimple1() public {
        MemoryKV kv_ = MemoryKV.wrap(0);
        MemoryKVKey k0_ = MemoryKVKey.wrap(5808);
        MemoryKVVal v00_ = MemoryKVVal.wrap(720);
        kv_ = LibMemoryKV.setVal(kv_, k0_, v00_);
        MemoryKVPtr ptr0_ = LibMemoryKV.getPtr(kv_, k0_);
        assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(ptr0_)), MemoryKVVal.unwrap(v00_));

        MemoryKVKey k1_ = MemoryKVKey.wrap(4571);
        MemoryKVVal v10_ = MemoryKVVal.wrap(4142);
        kv_ = LibMemoryKV.setVal(kv_, k1_, v10_);
        MemoryKVPtr ptr1_ = LibMemoryKV.getPtr(kv_, k0_);
        assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(ptr1_)), MemoryKVVal.unwrap(v00_));
        MemoryKVPtr ptr2_ = LibMemoryKV.getPtr(kv_, k1_);
        assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(ptr2_)), MemoryKVVal.unwrap(v10_));
    }

    function testSetReadVal1Regression0() public {
        testSetReadVal1(
            MemoryKVKey.wrap(3),
            MemoryKVVal.wrap(1),
            MemoryKVVal.wrap(0),
            MemoryKVKey.wrap(3581604925786513772212354200143269148885062266247748192144976155057186124456),
            MemoryKVVal.wrap(0),
            MemoryKVVal.wrap(0)
        );
    }

    function testSetReadVal1(
        MemoryKVKey k0_,
        MemoryKVVal v00_,
        MemoryKVVal v01_,
        MemoryKVKey k1_,
        MemoryKVVal v10_,
        MemoryKVVal v11_
    ) public {
        vm.assume(MemoryKVKey.unwrap(k0_) != MemoryKVKey.unwrap(k1_));

        MemoryKV kv_ = MemoryKV.wrap(0);

        {
            assertTrue(LibMemory.memoryIsAligned());
            Pointer alloc0_ = LibPointer.allocatedMemoryPointer();
            kv_ = LibMemoryKV.setVal(kv_, k0_, v00_);
            Pointer alloc1_ = LibPointer.allocatedMemoryPointer();
            assertTrue(Pointer.unwrap(alloc1_) == Pointer.unwrap(alloc0_) + 0x60);
            assertTrue(LibMemory.memoryIsAligned());

            assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(LibMemoryKV.getPtr(kv_, k0_))), MemoryKVVal.unwrap(v00_));
            assertEq(MemoryKVPtr.unwrap(LibMemoryKV.getPtr(kv_, k1_)), 0);
        }

        {
            assertTrue(LibMemory.memoryIsAligned());
            Pointer alloc2_ = LibPointer.allocatedMemoryPointer();
            kv_ = LibMemoryKV.setVal(kv_, k1_, v10_);
            Pointer alloc3_ = LibPointer.allocatedMemoryPointer();
            assertTrue(LibMemory.memoryIsAligned());
            assertTrue(Pointer.unwrap(alloc3_) == Pointer.unwrap(alloc2_) + 0x60);

            assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(LibMemoryKV.getPtr(kv_, k0_))), MemoryKVVal.unwrap(v00_));
            assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(LibMemoryKV.getPtr(kv_, k1_))), MemoryKVVal.unwrap(v10_));
        }

        {
            assertTrue(LibMemory.memoryIsAligned());
            Pointer alloc4_ = LibPointer.allocatedMemoryPointer();
            kv_ = LibMemoryKV.setVal(kv_, k1_, v11_);
            Pointer alloc5_ = LibPointer.allocatedMemoryPointer();
            assertTrue(LibMemory.memoryIsAligned());
            // No alloc on update.
            assertTrue(Pointer.unwrap(alloc4_) == Pointer.unwrap(alloc5_));

            assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(LibMemoryKV.getPtr(kv_, k0_))), MemoryKVVal.unwrap(v00_));
            assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(LibMemoryKV.getPtr(kv_, k1_))), MemoryKVVal.unwrap(v11_));
        }

        {
            assertTrue(LibMemory.memoryIsAligned());
            Pointer alloc6_ = LibPointer.allocatedMemoryPointer();

            kv_ = LibMemoryKV.setVal(kv_, k0_, v01_);
            Pointer alloc7_ = LibPointer.allocatedMemoryPointer();

            assertTrue(LibMemory.memoryIsAligned());
            // No alloc on update.
            assertTrue(Pointer.unwrap(alloc6_) == Pointer.unwrap(alloc7_));

            assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(LibMemoryKV.getPtr(kv_, k0_))), MemoryKVVal.unwrap(v01_));
            assertEq(MemoryKVVal.unwrap(LibMemoryKV.readPtrVal(LibMemoryKV.getPtr(kv_, k1_))), MemoryKVVal.unwrap(v11_));
        }
    }

    function testReadPtrValGas() public pure {
        // This is an illegal read but it gives the cost without memory
        // expansion costs etc.
        LibMemoryKV.readPtrVal(MemoryKVPtr.wrap(0));
    }

    function testGetPtrGas() public pure {
        MemoryKV kv_ = MemoryKV.wrap(0);
        LibMemoryKV.getPtr(kv_, MemoryKVKey.wrap(0));
    }

    function testSetValGas0() public pure {
        MemoryKV kv_ = MemoryKV.wrap(0);
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
    }

    function testSetValGas1() public pure {
        MemoryKV kv_ = MemoryKV.wrap(0);
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
    }

    function testSetValGas3() public pure {
        MemoryKV kv_ = MemoryKV.wrap(0);
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
    }

    function testSetValGas4() public pure {
        MemoryKV kv_ = MemoryKV.wrap(0);
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(7), MemoryKVVal.wrap(8));
    }

    function testSetValGas5() public pure {
        MemoryKV kv_ = MemoryKV.wrap(0);
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(7), MemoryKVVal.wrap(8));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(9), MemoryKVVal.wrap(10));
    }

    function testSetValGas6() public pure {
        MemoryKV kv_ = MemoryKV.wrap(0);
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(7), MemoryKVVal.wrap(8));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(9), MemoryKVVal.wrap(10));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(10), MemoryKVVal.wrap(2));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(30), MemoryKVVal.wrap(4));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(50), MemoryKVVal.wrap(6));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(70), MemoryKVVal.wrap(8));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(90), MemoryKVVal.wrap(10));
    }

    function testUint256ArrayGas0() public pure {
        MemoryKV kv_ = MemoryKV.wrap(0);
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        uint256[] memory arr_ = LibMemoryKV.toUint256Array(kv_);
        (arr_);
    }

    function testUint256ArrayGas1() public pure {
        MemoryKV kv_ = MemoryKV.wrap(0);
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        uint256[] memory arr_ = LibMemoryKV.toUint256Array(kv_);
        (arr_);
    }

    function testUint256ArrayGas3() public pure {
        MemoryKV kv_ = MemoryKV.wrap(0);
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        uint256[] memory arr_ = LibMemoryKV.toUint256Array(kv_);
        (arr_);
    }

    function testUint256ArrayGas4() public pure {
        MemoryKV kv_ = MemoryKV.wrap(0);
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(7), MemoryKVVal.wrap(8));
        uint256[] memory arr_ = LibMemoryKV.toUint256Array(kv_);
        (arr_);
    }

    function testUint256ArrayGas5() public pure {
        MemoryKV kv_ = MemoryKV.wrap(0);
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(7), MemoryKVVal.wrap(8));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(9), MemoryKVVal.wrap(10));
        uint256[] memory arr_ = LibMemoryKV.toUint256Array(kv_);
        (arr_);
    }

    function testUint256ArrayGas6() public pure {
        MemoryKV kv_ = MemoryKV.wrap(0);
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(1), MemoryKVVal.wrap(2));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(3), MemoryKVVal.wrap(4));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(5), MemoryKVVal.wrap(6));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(7), MemoryKVVal.wrap(8));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(9), MemoryKVVal.wrap(10));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(10), MemoryKVVal.wrap(2));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(30), MemoryKVVal.wrap(4));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(50), MemoryKVVal.wrap(6));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(70), MemoryKVVal.wrap(8));
        kv_ = LibMemoryKV.setVal(kv_, MemoryKVKey.wrap(90), MemoryKVVal.wrap(10));
        uint256[] memory arr_ = LibMemoryKV.toUint256Array(kv_);
        (arr_);
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
