// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract TokenAirdrop {
    address public owner;

    event AirdropExecuted(address indexed token, uint256 totalRecipients, uint256 totalAmount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function airdropEqualAmount(address token, address[] calldata recipients, uint256 amount) external onlyOwner {
        require(recipients.length > 0, "No recipients provided");
        require(amount > 0, "Amount must be greater than 0");

        IERC20 tokenContract = IERC20(token);
        uint256 totalAmount = amount * recipients.length;

        require(tokenContract.balanceOf(address(this)) >= totalAmount, "Insufficient token balance in contract");

        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient address");
            require(tokenContract.transfer(recipients[i], amount), "Token transfer failed");
        }

        emit AirdropExecuted(token, recipients.length, totalAmount);
    }

    function airdropDifferentAmounts(address token, address[] calldata recipients, uint256[] calldata amounts)
        external
        onlyOwner
    {
        require(recipients.length > 0, "No recipients provided");
        require(recipients.length == amounts.length, "Arrays length mismatch");

        IERC20 tokenContract = IERC20(token);
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "Amount must be greater than 0");
            totalAmount += amounts[i];
        }

        require(tokenContract.balanceOf(address(this)) >= totalAmount, "Insufficient token balance in contract");

        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient address");
            require(tokenContract.transfer(recipients[i], amounts[i]), "Token transfer failed");
        }

        emit AirdropExecuted(token, recipients.length, totalAmount);
    }

    function airdropBatch(
        address token,
        address[] calldata recipients,
        uint256 amount,
        uint256 startIndex,
        uint256 endIndex
    ) external onlyOwner {
        require(startIndex < endIndex, "Invalid batch range");
        require(endIndex <= recipients.length, "End index out of bounds");
        require(amount > 0, "Amount must be greater than 0");

        IERC20 tokenContract = IERC20(token);
        uint256 batchSize = endIndex - startIndex;
        uint256 totalAmount = amount * batchSize;

        require(tokenContract.balanceOf(address(this)) >= totalAmount, "Insufficient token balance in contract");

        for (uint256 i = startIndex; i < endIndex; i++) {
            require(recipients[i] != address(0), "Invalid recipient address");
            require(tokenContract.transfer(recipients[i], amount), "Token transfer failed");
        }

        emit AirdropExecuted(token, batchSize, totalAmount);
    }

    function depositTokens(address token, uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");

        IERC20 tokenContract = IERC20(token);
        require(tokenContract.transferFrom(msg.sender, address(this), amount), "Token deposit failed");
    }

    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));

        if (amount == 0) {
            amount = balance;
        }

        require(amount <= balance, "Insufficient balance");
        require(tokenContract.transfer(owner, amount), "Token withdrawal failed");
    }

    function getTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
