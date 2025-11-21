// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IPolicy} from "../interfaces/IPolicy.sol";
import {Types} from "../libraries/Types.sol";

abstract contract BasePolicy is IPolicy {
    function validate(
        Types.SessionAuth calldata auth,
        Types.Call[] calldata calls
    ) external view virtual override returns (bool ok, uint256 code) {
        // 기본 구현은 항상 false 반환
        // 하위 클래스에서 오버라이드해야 함
        // auth와 calls는 사용되지 않지만 인터페이스 호환성을 위해 유지
        auth;
        calls;
        return (false, 0);
    }
}

