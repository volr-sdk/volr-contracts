// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VolrInvoker} from "../../../src/invoker/VolrInvoker.sol";
import {PolicyRegistry} from "../../../src/registry/PolicyRegistry.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {TestHelpers} from "../../helpers/TestHelpers.sol";
import {MockSponsor} from "../../helpers/MockContracts.sol";

/**
 * @title TokenReceiverTest
 * @notice Unit tests for ERC721/ERC1155 receiver functionality
 */
contract TokenReceiverTest is Test {
    VolrInvoker public invoker;
    
    function setUp() public {
        MockSponsor mockSponsor = new MockSponsor();
        PolicyRegistry registry = TestHelpers.deployPolicyRegistry(address(this));
        invoker = TestHelpers.deployVolrInvoker(
            address(this),
            address(registry),
            address(mockSponsor)
        );
    }
    
    // ============ ERC721 Receiver ============
    
    function test_onERC721Received_ReturnsCorrectSelector() public view {
        bytes4 result = invoker.onERC721Received(
            address(0),
            address(0),
            0,
            ""
        );
        
        assertEq(result, IERC721Receiver.onERC721Received.selector);
        assertEq(result, bytes4(0x150b7a02));
    }
    
    function test_onERC721Received_AcceptsAnyParameters() public view {
        // Test with various parameters
        bytes4 result = invoker.onERC721Received(
            address(0x1234),
            address(0x5678),
            12345,
            hex"deadbeef"
        );
        
        assertEq(result, IERC721Receiver.onERC721Received.selector);
    }
    
    // ============ ERC1155 Receiver ============
    
    function test_onERC1155Received_ReturnsCorrectSelector() public view {
        bytes4 result = invoker.onERC1155Received(
            address(0),
            address(0),
            0,
            0,
            ""
        );
        
        assertEq(result, IERC1155Receiver.onERC1155Received.selector);
        assertEq(result, bytes4(0xf23a6e61));
    }
    
    function test_onERC1155Received_AcceptsAnyParameters() public view {
        bytes4 result = invoker.onERC1155Received(
            address(0x1234),
            address(0x5678),
            100,
            50,
            hex"cafebabe"
        );
        
        assertEq(result, IERC1155Receiver.onERC1155Received.selector);
    }
    
    function test_onERC1155BatchReceived_ReturnsCorrectSelector() public view {
        uint256[] memory ids = new uint256[](0);
        uint256[] memory amounts = new uint256[](0);
        
        bytes4 result = invoker.onERC1155BatchReceived(
            address(0),
            address(0),
            ids,
            amounts,
            ""
        );
        
        assertEq(result, IERC1155Receiver.onERC1155BatchReceived.selector);
        assertEq(result, bytes4(0xbc197c81));
    }
    
    function test_onERC1155BatchReceived_AcceptsAnyParameters() public view {
        uint256[] memory ids = new uint256[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10;
        amounts[1] = 20;
        amounts[2] = 30;
        
        bytes4 result = invoker.onERC1155BatchReceived(
            address(0x1234),
            address(0x5678),
            ids,
            amounts,
            hex"12345678"
        );
        
        assertEq(result, IERC1155Receiver.onERC1155BatchReceived.selector);
    }
    
    // ============ ERC165 ============
    
    function test_supportsInterface_ERC165() public view {
        bool result = invoker.supportsInterface(type(IERC165).interfaceId);
        assertTrue(result);
        
        // Verify the interface ID
        assertEq(type(IERC165).interfaceId, bytes4(0x01ffc9a7));
    }
    
    function test_supportsInterface_ERC721Receiver() public view {
        bool result = invoker.supportsInterface(type(IERC721Receiver).interfaceId);
        assertTrue(result);
        
        // Verify the interface ID
        assertEq(type(IERC721Receiver).interfaceId, bytes4(0x150b7a02));
    }
    
    function test_supportsInterface_ERC1155Receiver() public view {
        bool result = invoker.supportsInterface(type(IERC1155Receiver).interfaceId);
        assertTrue(result);
        
        // Verify the interface ID
        assertEq(type(IERC1155Receiver).interfaceId, bytes4(0x4e2312e0));
    }
    
    function test_supportsInterface_UnsupportedInterface() public view {
        // Random interface ID that we don't support
        bytes4 randomInterface = bytes4(0xdeadbeef);
        bool result = invoker.supportsInterface(randomInterface);
        assertFalse(result);
    }
    
    function test_supportsInterface_AllSupportedInterfaces() public view {
        // Test all supported interfaces in one go
        assertTrue(invoker.supportsInterface(0x01ffc9a7)); // ERC165
        assertTrue(invoker.supportsInterface(0x150b7a02)); // ERC721Receiver
        assertTrue(invoker.supportsInterface(0x4e2312e0)); // ERC1155Receiver
        assertTrue(invoker.supportsInterface(0x88a7ca5c)); // IERC1363Receiver
        assertTrue(invoker.supportsInterface(0x7b04a2d0)); // IERC1363Spender
        assertTrue(invoker.supportsInterface(0x0023de29)); // IERC777Recipient
    }
    
    // ============ ERC-1363 Receiver ============
    
    function test_onTransferReceived_ReturnsCorrectSelector() public view {
        bytes4 result = invoker.onTransferReceived(
            address(0),
            address(0),
            0,
            ""
        );
        
        assertEq(result, bytes4(keccak256("onTransferReceived(address,address,uint256,bytes)")));
    }
    
    function test_onApprovalReceived_ReturnsCorrectSelector() public view {
        bytes4 result = invoker.onApprovalReceived(
            address(0),
            0,
            ""
        );
        
        assertEq(result, bytes4(keccak256("onApprovalReceived(address,uint256,bytes)")));
    }
    
    // ============ ERC-777 Receiver ============
    
    function test_tokensReceived_DoesNotRevert() public view {
        // Just verify it doesn't revert
        invoker.tokensReceived(
            address(0),
            address(0),
            address(0),
            0,
            "",
            ""
        );
        // If we get here, the function didn't revert
        assertTrue(true);
    }
}

