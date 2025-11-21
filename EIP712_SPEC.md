# Volr EIP-712 Canonical Specification

이 문서는 `volr-contracts/src/libraries/EIP712.sol`과 `volr-contracts/src/libraries/Types.sol`을 단일 소스로 삼아 SDK, 백엔드, 스크립트가 동일한 서명 메시지를 생성할 수 있도록 필드 순서와 타입을 표 형태로 정리한다.

## Domain Separator

| Field | Value |
| --- | --- |
| `name` | `"volr"` |
| `version` | `"1"` |
| `chainId` | 실행 체인의 `uint256` |
| `verifyingContract` | Invoker 컨트랙트 주소 (`address`) |

## `Types.SessionAuth`

| 순서 | 필드 | Solidity 타입 | 설명 |
| --- | --- | --- | --- |
| 1 | `chainId` | `uint256` | 메세지 체인 ID (도메인 chainId와 동일) |
| 2 | `sessionKey` | `address` | 서명자 EOA |
| 3 | `sessionId` | `uint64` | 프로젝트 정의 세션 식별자 |
| 4 | `nonce` | `uint64` | per-session keyed nonce (Invoker `channelNonces`) |
| 5 | `expiresAt` | `uint64` | Unix 타임스탬프 |
| 6 | `policyId` | `bytes32` | Registry policy identifier |
| 7 | `policySnapshotHash` | `bytes32` | 정책 스냅샷(allow list + 코드 해시) 고정 |
| 8 | `gasLimitMax` | `uint256` | 단일 call gas 상한 |
| 9 | `maxFeePerGas` | `uint256` | EIP-1559 `maxFeePerGas` 상한 |
| 10 | `maxPriorityFeePerGas` | `uint256` | EIP-1559 `maxPriorityFeePerGas` 상한 |
| 11 | `totalGasCap` | `uint256` | 배치 전체 가스 한도 |

## `Types.Call`

| 순서 | 필드 | Solidity 타입 | 설명 |
| --- | --- | --- | --- |
| 1 | `target` | `address` | 호출 대상 컨트랙트 |
| 2 | `value` | `uint256` | `call.value` (현재 0 고정) |
| 3 | `data` | `bytes` | ABI 인코딩된 calldata |
| 4 | `gasLimit` | `uint256` | 각 call에 허용되는 가스 |

## `SignedBatch` Typed Data

```
SignedBatch(SessionAuth auth, Call[] calls, bool revertOnFail, bytes32 callsHash)
Call(address target, bytes data, uint256 value, uint256 gasLimit)
SessionAuth(...)
```

- `revertOnFail`는 기본 `true`.
- `callsHash`는 `keccak256(abi.encode(tuple(address,uint256,bytes,uint256)[] calls))`.
- 모든 hex 필드는 `0x` prefix + 소문자로 정규화한다.

## 공유 Fixture

- 경로: `volr-contracts/test/fixtures/eip712-session.json`
- 내용: canonical SessionAuth, Calls, Domain, `callsHash`, `digest`.
- SDK/백엔드는 해당 JSON을 직접 로드하여 기대 digest와 동일한지 테스트해야 한다.

## Foundry 테스트

- `test/unit/EIP712Session.t.sol`은 fixture를 읽어 `EIP712.hashSignedBatch` 결과가 JSON에 정의된 digest와 일치하는지 검증한다.
- 이 테스트가 성공하면 컨트랙트 쪽 타입 정의가 canonical fixture와 동기화되어 있음을 의미한다.


