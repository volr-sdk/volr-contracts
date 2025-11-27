// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/**
 * @title MockTarget
 * @notice Simple mock contract for testing call execution
 */
contract MockTarget {
    uint256 public counter;
    uint256 public lastValue;
    bytes public lastData;
    address public lastCaller;
    
    event Called(address indexed caller, uint256 value, bytes data);
    event CounterIncremented(uint256 newValue);
    
    error CustomError(string message);
    error InsufficientValue(uint256 required, uint256 provided);
    
    function increment() external returns (uint256) {
        counter++;
        emit CounterIncremented(counter);
        return counter;
    }
    
    function incrementBy(uint256 amount) external returns (uint256) {
        counter += amount;
        emit CounterIncremented(counter);
        return counter;
    }
    
    function setCounter(uint256 value) external {
        counter = value;
    }
    
    function payableIncrement() external payable returns (uint256) {
        lastValue = msg.value;
        lastCaller = msg.sender;
        counter++;
        emit Called(msg.sender, msg.value, msg.data);
        return counter;
    }
    
    function requireValue(uint256 minValue) external payable {
        if (msg.value < minValue) {
            revert InsufficientValue(minValue, msg.value);
        }
        lastValue = msg.value;
    }
    
    function alwaysRevert() external pure {
        revert CustomError("Always reverts");
    }
    
    function revertWithMessage(string calldata message) external pure {
        revert CustomError(message);
    }
    
    function recordCall() external payable {
        lastCaller = msg.sender;
        lastValue = msg.value;
        lastData = msg.data;
        emit Called(msg.sender, msg.value, msg.data);
    }
    
    function getState() external view returns (uint256, address, uint256) {
        return (counter, lastCaller, lastValue);
    }
    
    receive() external payable {
        lastValue = msg.value;
        lastCaller = msg.sender;
    }
}

/**
 * @title MockERC20
 * @notice Simple mock ERC20 for testing
 */
contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function burn(address from, uint256 amount) external {
        require(balanceOf[from] >= amount, "Insufficient balance");
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}

/**
 * @title MockERC721
 * @notice Simple mock ERC721 for testing safeTransfer
 */
contract MockERC721 {
    string public name = "Mock NFT";
    string public symbol = "MNFT";
    
    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    
    uint256 private _nextTokenId = 1;
    
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    
    error ERC721InvalidReceiver(address receiver);
    
    function mint(address to) external returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        ownerOf[tokenId] = to;
        balanceOf[to]++;
        emit Transfer(address(0), to, tokenId);
    }
    
    function transferFrom(address from, address to, uint256 tokenId) public {
        require(ownerOf[tokenId] == from, "Not owner");
        require(
            msg.sender == from || 
            msg.sender == getApproved[tokenId] || 
            isApprovedForAll[from][msg.sender],
            "Not authorized"
        );
        
        balanceOf[from]--;
        balanceOf[to]++;
        ownerOf[tokenId] = to;
        delete getApproved[tokenId];
        
        emit Transfer(from, to, tokenId);
    }
    
    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }
    
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
                if (retval != IERC721Receiver.onERC721Received.selector) {
                    revert ERC721InvalidReceiver(to);
                }
            } catch {
                revert ERC721InvalidReceiver(to);
            }
        }
    }
    
    function approve(address to, uint256 tokenId) external {
        require(ownerOf[tokenId] == msg.sender, "Not owner");
        getApproved[tokenId] = to;
        emit Approval(msg.sender, to, tokenId);
    }
    
    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }
}

/**
 * @title MockERC1155
 * @notice Simple mock ERC1155 for testing safeTransfer
 */
contract MockERC1155 {
    mapping(uint256 => mapping(address => uint256)) public balanceOf;
    mapping(address => mapping(address => bool)) public isApprovedForAll;
    
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values);
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);
    
    error ERC1155InvalidReceiver(address receiver);
    
    function mint(address to, uint256 id, uint256 amount) external {
        balanceOf[id][to] += amount;
        emit TransferSingle(msg.sender, address(0), to, id, amount);
    }
    
    function mintBatch(address to, uint256[] calldata ids, uint256[] calldata amounts) external {
        require(ids.length == amounts.length, "Length mismatch");
        for (uint256 i = 0; i < ids.length; i++) {
            balanceOf[ids[i]][to] += amounts[i];
        }
        emit TransferBatch(msg.sender, address(0), to, ids, amounts);
    }
    
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external {
        require(
            msg.sender == from || isApprovedForAll[from][msg.sender],
            "Not authorized"
        );
        require(balanceOf[id][from] >= amount, "Insufficient balance");
        
        balanceOf[id][from] -= amount;
        balanceOf[id][to] += amount;
        
        emit TransferSingle(msg.sender, from, to, id, amount);
        
        if (to.code.length > 0) {
            try IERC1155Receiver(to).onERC1155Received(msg.sender, from, id, amount, data) returns (bytes4 retval) {
                if (retval != IERC1155Receiver.onERC1155Received.selector) {
                    revert ERC1155InvalidReceiver(to);
                }
            } catch {
                revert ERC1155InvalidReceiver(to);
            }
        }
    }
    
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external {
        require(
            msg.sender == from || isApprovedForAll[from][msg.sender],
            "Not authorized"
        );
        require(ids.length == amounts.length, "Length mismatch");
        
        for (uint256 i = 0; i < ids.length; i++) {
            require(balanceOf[ids[i]][from] >= amounts[i], "Insufficient balance");
            balanceOf[ids[i]][from] -= amounts[i];
            balanceOf[ids[i]][to] += amounts[i];
        }
        
        emit TransferBatch(msg.sender, from, to, ids, amounts);
        
        if (to.code.length > 0) {
            try IERC1155Receiver(to).onERC1155BatchReceived(msg.sender, from, ids, amounts, data) returns (bytes4 retval) {
                if (retval != IERC1155Receiver.onERC1155BatchReceived.selector) {
                    revert ERC1155InvalidReceiver(to);
                }
            } catch {
                revert ERC1155InvalidReceiver(to);
            }
        }
    }
    
    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }
    
    function balanceOfBatch(
        address[] calldata accounts,
        uint256[] calldata ids
    ) external view returns (uint256[] memory) {
        require(accounts.length == ids.length, "Length mismatch");
        uint256[] memory batchBalances = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            batchBalances[i] = balanceOf[ids[i]][accounts[i]];
        }
        return batchBalances;
    }
}

/**
 * @title MockSponsor
 * @notice Simple mock sponsor for testing
 */
contract MockSponsor {
    uint256 public totalSponsored;
    mapping(address => uint256) public userSponsored;
    mapping(bytes32 => uint256) public policySponsored;
    
    event SponsorshipHandled(address indexed user, uint256 gasUsed, bytes32 indexed policyId);
    event ClientCompensated(address indexed client, uint256 gasUsed, bytes32 indexed policyId);
    
    function handleSponsorship(
        address user,
        uint256 gasUsed,
        bytes32 policyId
    ) external {
        totalSponsored += gasUsed;
        userSponsored[user] += gasUsed;
        policySponsored[policyId] += gasUsed;
        emit SponsorshipHandled(user, gasUsed, policyId);
    }
    
    function compensateClient(
        address client,
        uint256 gasUsed,
        bytes32 policyId
    ) external {
        emit ClientCompensated(client, gasUsed, policyId);
    }
}

/**
 * @title ReentrantAttacker
 * @notice Contract for testing reentrancy protection
 */
contract ReentrantAttacker {
    address public target;
    bytes public attackData;
    uint256 public attackCount;
    bool public attacking;
    
    function setAttack(address _target, bytes calldata _data) external {
        target = _target;
        attackData = _data;
    }
    
    function attack() external {
        attacking = true;
        (bool success,) = target.call(attackData);
        require(success, "Initial attack failed");
        attacking = false;
    }
    
    receive() external payable {
        if (attacking && attackCount < 3) {
            attackCount++;
            (bool success,) = target.call(attackData);
            // Silently fail on reentrancy (expected behavior)
            success;
        }
    }
    
    fallback() external payable {
        if (attacking && attackCount < 3) {
            attackCount++;
            (bool success,) = target.call(attackData);
            success;
        }
    }
}

