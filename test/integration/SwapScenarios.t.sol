// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

/**
 * @title MockERC20
 * @notice 테스트용 ERC20 토큰
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
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
}

/**
 * @title MockRouter
 * @notice 테스트용 Uniswap 스타일 Router
 */
contract MockRouter {
    event SwapETHForTokens(address indexed user, uint256 ethAmount, uint256 tokenAmount);
    event SwapTokensForETH(address indexed user, uint256 tokenAmount, uint256 ethAmount);
    event SwapTokensForTokens(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    
    constructor(address _tokenA, address _tokenB) {
        tokenA = MockERC20(_tokenA);
        tokenB = MockERC20(_tokenB);
    }
    
    // ETH -> Token 스왑
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        require(msg.value > 0, "No ETH sent");
        require(block.timestamp <= deadline, "Expired");
        
        // 간단한 1:1 스왑 (실제로는 AMM 로직)
        uint256 tokenAmount = msg.value;
        require(tokenAmount >= amountOutMin, "Insufficient output");
        
        tokenA.mint(to, tokenAmount);
        
        emit SwapETHForTokens(msg.sender, msg.value, tokenAmount);
        
        amounts = new uint256[](2);
        amounts[0] = msg.value;
        amounts[1] = tokenAmount;
        return amounts;
    }
    
    // Token -> ETH 스왑
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "Expired");
        
        // msg.sender로부터 토큰 가져오기
        tokenA.transferFrom(msg.sender, address(this), amountIn);
        
        // ETH 전송 (1:1)
        uint256 ethAmount = amountIn;
        require(ethAmount >= amountOutMin, "Insufficient output");
        
        payable(to).transfer(ethAmount);
        
        emit SwapTokensForETH(msg.sender, amountIn, ethAmount);
        
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = ethAmount;
        return amounts;
    }
    
    // Token -> Token 스왑
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "Expired");
        
        // tokenA 가져오기
        tokenA.transferFrom(msg.sender, address(this), amountIn);
        
        // tokenB 전송 (1:1)
        uint256 amountOut = amountIn;
        require(amountOut >= amountOutMin, "Insufficient output");
        
        tokenB.mint(to, amountOut);
        
        emit SwapTokensForTokens(msg.sender, address(tokenA), address(tokenB), amountIn, amountOut);
        
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
        return amounts;
    }
    
    receive() external payable {}
}

/**
 * @title SwapScenariosTest
 * @notice 스왑 시나리오 통합 테스트
 * @dev EIP-7702에서 call을 사용할 때 msg.sender가 사용자 주소로 유지되는지 검증
 */
contract SwapScenariosTest is Test {
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockRouter public router;
    
    address public user = address(0x1234);
    address public recipient = address(0x5678);
    
    function setUp() public {
        // 토큰 및 Router 배포
        tokenA = new MockERC20();
        tokenB = new MockERC20();
        router = new MockRouter(address(tokenA), address(tokenB));
        
        // 초기 잔액 설정
        vm.deal(user, 10 ether);
        tokenA.mint(user, 1000 ether);
        vm.deal(address(router), 10 ether);
    }
    
    /**
     * @notice 테스트 1: ETH -> ERC20 스왑
     * @dev EIP-7702: user EOA가 Invoker 코드 실행 → call 사용 → msg.sender = user
     */
    function test_SwapETHForTokens() public {
        uint256 ethAmount = 1 ether;
        
        // 실행 전 잔액
        uint256 userETHBefore = user.balance;
        uint256 userTokenBefore = tokenA.balanceOf(user);
        
        // EIP-7702 시뮬레이션: user가 직접 router 호출
        // msg.sender = user
        vm.prank(user);
        address[] memory path = new address[](2);
        path[0] = address(0);
        path[1] = address(tokenA);
        router.swapExactETHForTokens{value: ethAmount}(
            ethAmount,
            path,
            user,
            block.timestamp + 3600
        );
        
        // 실행 후 잔액 확인
        assertEq(user.balance, userETHBefore - ethAmount, "ETH should be deducted");
        assertEq(tokenA.balanceOf(user), userTokenBefore + ethAmount, "Tokens should be received");
    }
    
    /**
     * @notice 테스트 2: ERC20 -> ETH 스왑
     * @dev approve + swap 배치 실행, msg.sender = user로 유지
     */
    function test_SwapTokensForETH() public {
        uint256 tokenAmount = 1 ether;
        
        uint256 userETHBefore = user.balance;
        uint256 userTokenBefore = tokenA.balanceOf(user);
        
        // msg.sender = user로 approve 실행
        vm.prank(user);
        tokenA.approve(address(router), tokenAmount);
        
        // msg.sender = user로 swap 실행
        vm.prank(user);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(0);
        router.swapExactTokensForETH(tokenAmount, tokenAmount, path, user, block.timestamp + 3600);
        
        // 잔액 확인
        assertEq(tokenA.balanceOf(user), userTokenBefore - tokenAmount, "Tokens should be deducted");
        assertEq(user.balance, userETHBefore + tokenAmount, "ETH should be received");
    }
    
    /**
     * @notice 테스트 3: ERC20 -> ERC20 스왑
     * @dev approve + swap 배치 실행, msg.sender = user로 유지
     */
    function test_SwapTokensForTokens() public {
        uint256 tokenAmount = 1 ether;
        
        uint256 userTokenABefore = tokenA.balanceOf(user);
        uint256 userTokenBBefore = tokenB.balanceOf(user);
        
        // msg.sender = user로 approve 실행
        vm.prank(user);
        tokenA.approve(address(router), tokenAmount);
        
        // msg.sender = user로 swap 실행
        vm.prank(user);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        router.swapExactTokensForTokens(tokenAmount, tokenAmount, path, user, block.timestamp + 3600);
        
        // 잔액 확인
        assertEq(tokenA.balanceOf(user), userTokenABefore - tokenAmount, "TokenA should be deducted");
        assertEq(tokenB.balanceOf(user), userTokenBBefore + tokenAmount, "TokenB should be received");
    }
    
    /**
     * @notice 테스트 4: msg.sender 검증 - ERC20 transfer
     * @dev EIP-7702에서 call 사용 시 msg.sender가 사용자 주소인지 확인
     */
    function test_MsgSenderIsUser_ERC20Transfer() public {
        uint256 amount = 100 ether;
        
        uint256 userBalance = tokenA.balanceOf(user);
        assertGt(userBalance, amount, "User should have tokens");
        
        // msg.sender = user로 transfer 실행
        vm.prank(user);
        bool success = tokenA.transfer(recipient, amount);
        
        assertTrue(success, "Transfer should succeed");
        assertEq(tokenA.balanceOf(user), userBalance - amount, "User balance should decrease");
        assertEq(tokenA.balanceOf(recipient), amount, "Recipient should receive tokens");
    }
    
    /**
     * @notice 테스트 5: approve 없이 transfer 직접 사용
     * @dev EIP-7702의 핵심: msg.sender = user이므로 approve 불필요
     */
    function test_DirectTransferWithoutApprove() public {
        uint256 amount = 100 ether;
        
        uint256 userBalanceBefore = tokenA.balanceOf(user);
        
        // EIP-7702: user EOA가 Invoker 코드 실행 → call 사용 → msg.sender = user
        vm.prank(user);
        tokenA.transfer(recipient, amount);
        
        assertEq(tokenA.balanceOf(user), userBalanceBefore - amount, "User balance should decrease");
        assertEq(tokenA.balanceOf(recipient), amount, "Recipient should receive tokens");
    }
}

