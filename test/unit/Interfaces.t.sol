// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IInvoker} from "../../src/interfaces/IInvoker.sol";
import {IPolicy} from "../../src/interfaces/IPolicy.sol";
import {ISponsor} from "../../src/interfaces/ISponsor.sol";
import {Types} from "../../src/libraries/Types.sol";

contract InterfacesTest is Test {
    function test_IInvoker_Interface() public {
        // 인터페이스가 컴파일되는지 확인
        // 실제 구현이 없어도 인터페이스 정의만으로 테스트
        assertTrue(true);
    }
    
    function test_IPolicy_Interface() public {
        // 인터페이스가 컴파일되는지 확인
        assertTrue(true);
    }
    
    function test_ISponsor_Interface() public {
        // 인터페이스가 컴파일되는지 확인
        assertTrue(true);
    }
}

