// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IKAP20S {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function mint(address _to, uint256 _amount) external returns (bool);

    function burn(address _from, uint256 _amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
}
