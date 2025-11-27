// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {VolrInvoker} from "../../src/invoker/VolrInvoker.sol";
import {ScopedPolicy} from "../../src/policy/ScopedPolicy.sol";
import {PolicyRegistry} from "../../src/registry/PolicyRegistry.sol";
import {Types} from "../../src/libraries/Types.sol";

import {TestHelpers} from "../helpers/TestHelpers.sol";
import {SignatureHelper} from "../helpers/SignatureHelper.sol";
import {MockERC721, MockERC1155, MockSponsor} from "../helpers/MockContracts.sol";

/**
 * @title TokenReceiverIntegrationTest
 * @notice Integration tests for ERC721/ERC1155 safe transfers to EIP-7702 delegated EOA
 */
contract TokenReceiverIntegrationTest is Test {
    VolrInvoker public invoker;
    ScopedPolicy public policy;
    MockERC721 public nft;
    MockERC1155 public multiToken;
    MockSponsor public mockSponsor;
    
    address public owner;
    address public user;
    uint256 public userKey;
    bytes32 public policyId;
    bytes32 public policySnapshotHash;
    
    function setUp() public {
        owner = address(this);
        userKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        user = vm.addr(userKey);
        policyId = keccak256("test-policy");
        
        // Deploy contracts
        nft = new MockERC721();
        multiToken = new MockERC1155();
        mockSponsor = new MockSponsor();
        policy = new ScopedPolicy();
        
        PolicyRegistry registry = TestHelpers.deployPolicyRegistry(owner);
        registry.setTimelock(owner);
        registry.setMultisig(owner);
        registry.register(policyId, address(policy), "test-policy");
        
        invoker = TestHelpers.deployVolrInvoker(owner, address(registry), address(mockSponsor));
        
        policy.setPolicy(policyId, block.chainid, type(uint256).max, type(uint64).max, true);
        (, , , policySnapshotHash, ) = policy.policies(policyId);
    }
    
    // ============ ERC721 safeTransfer Tests ============
    
    function test_ERC721_SafeTransferToInvoker_Success() public {
        // Mint NFT to this contract
        uint256 tokenId = nft.mint(address(this));
        
        // Transfer to invoker using safeTransferFrom
        nft.safeTransferFrom(address(this), address(invoker), tokenId);
        
        // Assert
        assertEq(nft.ownerOf(tokenId), address(invoker));
    }
    
    function test_ERC721_SafeTransferWithData_Success() public {
        uint256 tokenId = nft.mint(address(this));
        
        nft.safeTransferFrom(address(this), address(invoker), tokenId, hex"cafebabe");
        
        assertEq(nft.ownerOf(tokenId), address(invoker));
    }
    
    function test_ERC721_MintDirectlyToInvoker_Success() public {
        // Mint directly to invoker (simulating a mint that uses safeTransfer internally)
        // Note: Our mock mint doesn't use safeTransfer, but we can test the receiver
        uint256 tokenId = nft.mint(address(invoker));
        
        assertEq(nft.ownerOf(tokenId), address(invoker));
    }
    
    function test_ERC721_TransferViaExecuteBatch() public {
        // Mint NFT to user
        uint256 tokenId = nft.mint(user);
        
        // User approves invoker
        vm.prank(user);
        nft.approve(address(invoker), tokenId);
        
        // Create call to transfer NFT from user to invoker
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = SignatureHelper.createCall(
            address(nft),
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", user, address(invoker), tokenId)
        );
        
        Types.SessionAuth memory auth = SignatureHelper.createDefaultAuth(
            block.chainid,
            user,
            policyId,
            policySnapshotHash
        );
        
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes memory sig = SignatureHelper.signSessionAuth(
            userKey,
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        // Execute
        invoker.executeBatch(calls, auth, false, callsHash, sig);
        
        // Assert
        assertEq(nft.ownerOf(tokenId), address(invoker));
    }
    
    // ============ ERC1155 safeTransfer Tests ============
    
    function test_ERC1155_SafeTransferToInvoker_Success() public {
        // Mint tokens to this contract
        uint256 tokenId = 1;
        uint256 amount = 100;
        multiToken.mint(address(this), tokenId, amount);
        
        // Approve and transfer
        multiToken.setApprovalForAll(address(this), true);
        multiToken.safeTransferFrom(address(this), address(invoker), tokenId, amount, "");
        
        // Assert
        assertEq(multiToken.balanceOf(tokenId, address(invoker)), amount);
    }
    
    function test_ERC1155_SafeTransferWithData_Success() public {
        uint256 tokenId = 1;
        uint256 amount = 50;
        multiToken.mint(address(this), tokenId, amount);
        
        multiToken.setApprovalForAll(address(this), true);
        multiToken.safeTransferFrom(address(this), address(invoker), tokenId, amount, hex"12345678");
        
        assertEq(multiToken.balanceOf(tokenId, address(invoker)), amount);
    }
    
    function test_ERC1155_SafeBatchTransferToInvoker_Success() public {
        // Mint multiple token types
        uint256[] memory ids = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        amounts[0] = 10;
        amounts[1] = 20;
        amounts[2] = 30;
        
        multiToken.mintBatch(address(this), ids, amounts);
        
        // Batch transfer
        multiToken.setApprovalForAll(address(this), true);
        multiToken.safeBatchTransferFrom(address(this), address(invoker), ids, amounts, "");
        
        // Assert
        assertEq(multiToken.balanceOf(ids[0], address(invoker)), amounts[0]);
        assertEq(multiToken.balanceOf(ids[1], address(invoker)), amounts[1]);
        assertEq(multiToken.balanceOf(ids[2], address(invoker)), amounts[2]);
    }
    
    function test_ERC1155_TransferViaExecuteBatch() public {
        uint256 tokenId = 1;
        uint256 amount = 100;
        
        // Mint to user
        multiToken.mint(user, tokenId, amount);
        
        // User approves invoker
        vm.prank(user);
        multiToken.setApprovalForAll(address(invoker), true);
        
        // Create call to transfer tokens
        Types.Call[] memory calls = new Types.Call[](1);
        calls[0] = SignatureHelper.createCall(
            address(multiToken),
            abi.encodeCall(multiToken.safeTransferFrom, (user, address(invoker), tokenId, amount, ""))
        );
        
        Types.SessionAuth memory auth = SignatureHelper.createDefaultAuth(
            block.chainid,
            user,
            policyId,
            policySnapshotHash
        );
        
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes memory sig = SignatureHelper.signSessionAuth(
            userKey,
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        // Execute
        invoker.executeBatch(calls, auth, false, callsHash, sig);
        
        // Assert
        assertEq(multiToken.balanceOf(tokenId, address(invoker)), amount);
    }
    
    // ============ Complex Scenarios ============
    
    function test_MixedTokenTransfers() public {
        // Setup: Mint NFT and ERC1155 to user
        uint256 nftTokenId = nft.mint(user);
        uint256 erc1155TokenId = 1;
        uint256 erc1155Amount = 50;
        multiToken.mint(user, erc1155TokenId, erc1155Amount);
        
        // User approves
        vm.startPrank(user);
        nft.approve(address(invoker), nftTokenId);
        multiToken.setApprovalForAll(address(invoker), true);
        vm.stopPrank();
        
        // Create batch call for both transfers
        Types.Call[] memory calls = new Types.Call[](2);
        calls[0] = SignatureHelper.createCall(
            address(nft),
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", user, address(invoker), nftTokenId)
        );
        calls[1] = SignatureHelper.createCall(
            address(multiToken),
            abi.encodeCall(multiToken.safeTransferFrom, (user, address(invoker), erc1155TokenId, erc1155Amount, ""))
        );
        
        Types.SessionAuth memory auth = SignatureHelper.createDefaultAuth(
            block.chainid,
            user,
            policyId,
            policySnapshotHash
        );
        
        bytes32 callsHash = keccak256(abi.encode(calls));
        bytes memory sig = SignatureHelper.signSessionAuth(
            userKey,
            address(invoker),
            auth,
            calls,
            false,
            callsHash
        );
        
        // Execute
        invoker.executeBatch(calls, auth, false, callsHash, sig);
        
        // Assert both transfers succeeded
        assertEq(nft.ownerOf(nftTokenId), address(invoker));
        assertEq(multiToken.balanceOf(erc1155TokenId, address(invoker)), erc1155Amount);
    }
}

