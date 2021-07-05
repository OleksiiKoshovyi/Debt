// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Debt is ERC20 {

    enum State {Active, Locked, Closed}
    State state;
    
    uint256 debtSize;
    uint256 paymentTerm;
    uint8 feePercent;
    address payable lender;

    uint256 debtPaidPart;
    mapping(address => uint256) payments;
    address[] payers;

    error OnlyLender();
    error TooLate(uint256 time);
    
    modifier onlyLender() {
        if (msg.sender != lender) {
            revert OnlyLender();
        }
        _;
    }

    modifier onlyBefore(uint _time) {
        if (block.timestamp >= _time) {
            revert TooLate(_time);
        }
        _;
    }

    event DebtPartPaid(uint256 time, uint256 amount);
    event DebtPaid(uint256 time, uint256 amount);
    event DebtClosed(uint256 time, uint256 _debt, uint256 _debtPaidPart);

    constructor (uint256 _debtSize, uint256 _paymentTerm, uint8 _feePercent) ERC20("DebtToken", "DBT") {
        paymentTerm = _paymentTerm;
        debtSize = _debtSize;
        feePercent = _feePercent;
        lender = payable(msg.sender);
        state = State.Active;
    }


    function DebtSize(uint256 _debtSize) public onlyLender() {
        require(debtSize > 0, "Debt has already been paid!");
        debtSize = _debtSize;
    }
    
    function DebtSize() public view returns(uint256) {
        return debtSize;
    }
    
    function PaymentTerm(uint256 _paymentTerm) public onlyLender() {
        paymentTerm = _paymentTerm;
    }
    
    function PaymentTerm() public view returns(uint256) {
        return paymentTerm;
    }
    
    function FeePercent(uint8 _feePercent) public onlyLender() {
        feePercent = _feePercent;
    }
    
    function FeePercent() public view returns(uint8) {
        return feePercent;
    }

    function Lender(address _lender) public onlyLender() {
        lender = payable(_lender);
    }
    
    function Lender() public view returns(address) {
        return lender;
    }


    function payDebt() payable public onlyBefore(paymentTerm) returns(bool) {
        require(state == State.Active, "Contract must be active!");
        require(debtSize > 0, "The debt is paid off!");
        
        _mint(address(this), msg.value);

        if (debtSize <= msg.value) {
            uint256 refund = msg.value - debtSize;
            payments[msg.sender] += debtSize;
            debtPaidPart += debtSize;
            debtSize = 0;
            if (refund > 0) {
                _burn(address(this), refund);
                (bool success, ) = payable(msg.sender).call{value:refund}("");
                require(success, "Transfer failed.");
            }
            
            emit DebtPaid(block.timestamp, msg.value);
            
            return true;
        }
        
        if (payments[msg.sender] == 0) {
            payers.push(msg.sender);
        }
        
        payments[msg.sender] += msg.value;
        debtSize -= msg.value;
        debtPaidPart += msg.value;
        
        addFee();
        
        emit DebtPartPaid(block.timestamp, msg.value);
        
        return true;
    }
    
    function addFee() internal {
        uint256 fee = debtSize * feePercent / 100;
        debtSize += fee;
    }
    
    function closeDebt() public onlyLender() {
        require(state == State.Active, "Contract must be active!");
        
        state = State.Locked;
        
        if (debtSize == 0) {
            _approve(address(this), lender, debtPaidPart);
            bool success = transferFrom(address(this), lender, debtPaidPart);
            require(success, "Transfer failed.");
        } else {
            refunAllPayments();
        }
        
        emit DebtClosed(block.timestamp, debtSize, debtPaidPart);
        
        state = State.Closed;
    }
    
    function refunAllPayments() payable public onlyLender() {
        require(state == State.Locked, "Contract must be locked!");
        
        for (uint256 i = 0; i < payers.length; i++) {
            address payer = payers[i];
            uint256 payment = payments[payer];
            if (payment != 0) {
                (bool success, ) = payable(payer).call{value:payment}("");
                require(success, "Transfer failed.");
            }
        }
        _burn(address(this), balanceOf(address(this)));
    }
    
}

