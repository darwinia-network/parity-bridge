pragma solidity ^0.4.23;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

// another one is ByzantineSimpleSwapBridge.
contract AtlantisSimpleSwapBridge is Ownable {
    using SafeMath for uint256;

    mapping (address => bool) public supportedTokens;

    uint256 public swapCount;

    uint256 public startTime;

    uint256 public maxSwapAmount;

    address public feeWallet;

    uint256 public minFee;

    uint256 public transitionRatio;    // default to 5000, denominator is 10000
    uint256 public transitionDuration;  // default to 6 hours

    /// Event created on initilizing token dex in source network.
    event TokenSwapped(
    uint256 indexed swapId, address from, bytes32 to, uint256 amount, address token, uint256 fee, uint256 srcNetwork, uint256 dstNetwork);

    event ClaimedTokens(address indexed _token, address indexed _controller, uint _amount);


    /// Constructor.
    constructor (
        address _feeWallet,
        uint256 _minFee,
        uint256 _transitionRatio,
        uint256 _maxSwapAmount,
        uint256 _startTime
    ) public
    {
        feeWallet = _feeWallet;
        minFee = _minFee;
        transitionRatio = _transitionRatio;
        maxSwapAmount = _maxSwapAmount;

        startTime = _startTime;
        
        transitionDuration = 6*3600;
    }

    //users initial the exchange token with token method of "approveAndCall" in the source chain network
    //then invoke the following function in this contract
    //_amount include the fee token
    function receiveApproval(address from, uint256 _amount, address _token, bytes _data) public {

        require(supportedTokens[_token], "Not suppoted token.");
        require(msg.sender == _token, "Invalid msg sender for this tx.");

        uint256 swapAmount;
        uint256 dstNetwork;
        bytes32 receipt;

        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize)
            swapAmount := mload(add(ptr, 164))
            dstNetwork := mload(add(ptr, 196))
            receipt :=  mload(add(ptr, 228))
        }

        require(startTime == 0 || now >= startTime, "Swap should be after the start time.");

        require(swapAmount <= maxSwapAmount, "Swap amount must be less than max swap amount.");
        require(swapAmount > 0, "Swap amount must be larger than zero.");

        uint256 requiredFee = querySwapFeeForNow(swapAmount);
        require(_amount >= swapAmount.add(requiredFee), "No enough of token amount are approved.");

        if(requiredFee > 0) {
            require(ERC20(_token).transferFrom(from, feeWallet, requiredFee), "Fee transfer failed.");
        }

        require(ERC20(_token).transferFrom(from, this, swapAmount), "Swap amount transfer failed.");

        emit TokenSwapped(swapCount, from, receipt, swapAmount, _token, requiredFee, 1, dstNetwork);
        
        swapCount = swapCount + 1;
    }

    function addSupportedToken(address _token) public onlyOwner {
        supportedTokens[_token] = true;
    }

    function removeSupportedToken(address _token) public onlyOwner {
        supportedTokens[_token] = false;
    }

    function changeStartTime(uint256 _startTime) public onlyOwner {
        startTime = _startTime;
    }

    function changeMaxSwapAmount(uint256 _maxSwapAmount) public onlyOwner {
        maxSwapAmount = _maxSwapAmount;
    }

    function changeFeeWallet(address _newFeeWallet) public onlyOwner {
        feeWallet = _newFeeWallet;
    }

    function changeMinFee(uint256 _minFee) public onlyOwner {
        minFee = _minFee;
    }

    function changeTransitionRatio(uint256 _transitionRatio) public onlyOwner {
        transitionRatio = _transitionRatio;
    }

    function changeTransitionDuration(uint256 _transitionDuration) public onlyOwner {
        transitionDuration = _transitionDuration;
    }

    function querySwapFeeForNow(uint256 _amount) public view returns (uint256) {
        return querySwapFee(_amount, now);
    }

    function querySwapFee(uint256 _amount, uint256 _time) public view returns (uint256) {
        if (startTime == 0 || _time >= (startTime + transitionDuration)) {
            return minFee;
        }

        uint256 requiredFee = transitionRatio.mul(_amount).mul(startTime.add(transitionDuration).sub(_time)).div(transitionDuration * 10000);

        if (requiredFee < minFee ){
            requiredFee = minFee;
        }

        return requiredFee;
    }

    function claimTokens(address _token) public onlyOwner {
        if (_token == 0x0) {
            address(msg.sender).transfer(address(this).balance);
            return;
        }

        ERC20 token = ERC20(_token);
        uint balance = token.balanceOf(this);
        token.transfer(address(msg.sender), balance);

        emit ClaimedTokens(_token, address(msg.sender), balance);
    }
}