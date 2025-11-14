// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

/**
 * @title EIP-7702 msg.sender 테스트
 * @notice EIP-7702에서 call 사용 시 msg.sender가 어떻게 설정되는지 확인
 */
contract MsgSenderChecker {
    address public lastSender;
    
    function checkSender() external {
        lastSender = msg.sender;
    }
}

contract ProxyCode {
    function callChecker(address checker) external {
        // call 사용
        (bool success,) = checker.call(abi.encodeWithSignature("checkSender()"));
        require(success, "Call failed");
    }
    
    function delegatecallChecker(address checker) external {
        // delegatecall 사용
        (bool success,) = checker.delegatecall(abi.encodeWithSignature("checkSender()"));
        require(success, "Delegatecall failed");
    }
}

contract EIP7702MsgSenderTest is Test {
    MsgSenderChecker public checker;
    ProxyCode public proxyCode;
    
    address public userEOA = address(0x1234);
    
    function setUp() public {
        checker = new MsgSenderChecker();
        proxyCode = new ProxyCode();
    }
    
    /**
     * @notice 일반 call: msg.sender = 호출자
     */
    function test_NormalCall() public {
        vm.prank(userEOA);
        checker.checkSender();
        
        assertEq(checker.lastSender(), userEOA, "msg.sender should be userEOA");
    }
    
    /**
     * @notice ProxyCode에서 call: msg.sender = ProxyCode 주소
     */
    function test_ProxyCallWithCall() public {
        vm.prank(userEOA);
        proxyCode.callChecker(address(checker));
        
        // call을 사용하면 msg.sender = 호출한 컨트랙트 = proxyCode
        assertEq(checker.lastSender(), address(proxyCode), "msg.sender should be proxyCode");
    }
    
    /**
     * @notice EIP-7702 시뮬레이션: userEOA가 ProxyCode 실행 + call
     * @dev vm.etch로 userEOA에 ProxyCode 배포
     */
    function test_EIP7702_WithCall() public {
        // EIP-7702 시뮬레이션: userEOA의 코드를 ProxyCode로 설정
        vm.etch(userEOA, address(proxyCode).code);
        
        // userEOA에서 callChecker 실행
        vm.prank(userEOA);
        ProxyCode(userEOA).callChecker(address(checker));
        
        // EIP-7702 + call: msg.sender는 ProxyCode를 실행 중인 주소 = userEOA
        assertEq(checker.lastSender(), userEOA, "msg.sender should be userEOA (EIP-7702)");
    }
    
    /**
     * @notice EIP-7702 시뮬레이션: userEOA가 ProxyCode 실행 + delegatecall
     */
    function test_EIP7702_WithDelegatecall() public {
        // EIP-7702 시뮬레이션
        vm.etch(userEOA, address(proxyCode).code);
        
        // userEOA에서 delegatecallChecker 실행
        vm.prank(userEOA);
        ProxyCode(userEOA).delegatecallChecker(address(checker));
        
        // EIP-7702 + delegatecall: msg.sender는 원래 호출자
        // delegatecall은 현재 context에서 실행되므로 lastSender는 userEOA의 storage에 저장됨
        // 하지만 MsgSenderChecker의 storage를 읽으므로 값이 없을 수 있음
    }
}


