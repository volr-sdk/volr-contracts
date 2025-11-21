# 스왑 시나리오 분석 (EIP-7702 + call)

## EIP-7702 실행 흐름

```
Relayer → 사용자 EOA (EIP-7702 authorization)
└─ 사용자 EOA가 Invoker 코드 실행
   └─ executeBatch()
      └─ target.call{value: X}(data)
         → msg.sender = 사용자 EOA ✅
```

## 시나리오 1: ETH → ERC20 스왑

```typescript
// Uniswap swapExactETHForTokens 호출
const call = {
  target: routerAddress,
  value: 1000000000000000000n, // 1 ETH
  data: encodeFunctionData({
    abi: routerAbi,
    functionName: 'swapExactETHForTokens',
    args: [amountOutMin, path, user.address, deadline]
  })
}
```

**실행:**
- `call` 사용 (value > 0)
- Router 입장에서 `msg.sender = 사용자 EOA`
- Router가 사용자 EOA로부터 1 ETH 받음
- 토큰을 `user.address`로 전송 ✅

## 시나리오 2: ERC20 → ETH 스왑

```typescript
// 1. Router에 토큰 approve
const approveCall = {
  target: tokenAddress,
  value: 0n,
  data: encodeFunctionData({
    abi: erc20Abi,
    functionName: 'approve',
    args: [routerAddress, amount]
  })
}

// 2. swapExactTokensForETH 호출
const swapCall = {
  target: routerAddress,
  value: 0n,
  data: encodeFunctionData({
    abi: routerAbi,
    functionName: 'swapExactTokensForETH',
    args: [amount, amountOutMin, path, user.address, deadline]
  })
}
```

**실행:**
- 두 call 모두 `call` 사용 (value = 0)
- approve: `msg.sender = 사용자 EOA` → 사용자가 Router에 권한 부여 ✅
- swap: Router가 사용자로부터 토큰 가져가고, ETH를 `user.address`로 전송 ✅

## 시나리오 3: ERC20 → ERC20 스왑

```typescript
// 1. Router에 토큰 approve
const approveCall = {
  target: tokenInAddress,
  value: 0n,
  data: encodeFunctionData({
    abi: erc20Abi,
    functionName: 'approve',
    args: [routerAddress, amountIn]
  })
}

// 2. swapExactTokensForTokens 호출
const swapCall = {
  target: routerAddress,
  value: 0n,
  data: encodeFunctionData({
    abi: routerAbi,
    functionName: 'swapExactTokensForTokens',
    args: [amountIn, amountOutMin, path, user.address, deadline]
  })
}
```

**실행:**
- 두 call 모두 `call` 사용 (value = 0)
- approve: `msg.sender = 사용자 EOA` → 사용자가 Router에 권한 부여 ✅
- swap: Router가 사용자로부터 tokenIn 가져가고, tokenOut을 `user.address`로 전송 ✅

## 결론

**모든 경우에 `call`만 사용하면 문제없음!**

- ETH 전송이 필요한 경우: `call{value: X}` 사용
- 토큰 전송만 필요한 경우: `call` 사용
- EIP-7702 덕분에 msg.sender가 항상 사용자 EOA로 유지됨

**delegatecall은 위험하고 불필요함:**
- 외부 컨트랙트의 storage를 현재 context에 덮어씀
- DeFi 프로토콜과의 상호작용에는 부적합





