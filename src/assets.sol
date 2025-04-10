// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IAmmFactory.sol";

/// @title A$$ETS Token Contract
/// @notice Implementation of the A$$ETS Finance token with tax and max balance mechanics
/// @dev Extends ERC20 with burning capability, permit functionality, and ownership controls
/// @dev Implements anti-snipe protection for the first 60 seconds of trading
/// @dev Trading cannot be closed once opened
/// @dev Sell burn tax cannot be increased once reduced
/// @dev Max wallet balance cannot be decreased once set
contract ASSETS is ERC20, ERC20Burnable, ERC20Permit, Ownable {
    using SafeERC20 for IERC20;

    uint256 public maxBalance = 30_000 ether;

    uint256 public constant TAX_CAP = 20_000;

    uint256 public buyTaxBasis = 100; // 1.00%
    uint256 public sellTaxBasis = 1_000; // 10.00%

    uint256 public constant ANTI_SNIPE_TAX = 5_000; // 50.00% for anti-snipe
    uint256 public constant ANTI_SNIPE_DURATION = 60 seconds; // first 60 seconds of trading

    mapping(address => bool) public isV2Pair; // true if the pair is a registered v2 pair

    mapping(address => bool) public isExempt; // true if the address is exempt from the max balance check, anti-snipe, and sell/buy tax

    address public taxReceiver = 0x1b2f2AFbC3De0dD4501584bff968242fAEC16208;

    uint256 public tradingOpenTime = 0;

    error OverMax(uint256 amount, uint256 max);
    error UnderMin(uint256 amount, uint256 max);
    error TradingNotOpen();
    error TradingAlreadyOpen();
    event MaxBalanceUpdated(uint256 oldMaxBalance, uint256 newMaxBalance);
    event SellTaxBasisUpdated(uint256 oldSellTaxBasis, uint256 newSellTaxBasis);
    event BuyTaxBasisUpdated(uint256 oldBuyTaxBasis, uint256 newBuyTaxBasis);
    event TaxReceiverUpdated(address oldTaxReceiver, address newTaxReceiver);

    /// @notice Initializes the token contract with trading parameters
    constructor()
        ERC20("A$$ETS Finance", "A$$ETS")
        ERC20Permit("A$$ETS")
        Ownable(0xb47b915cC85c00493917277E0389777fBd124752)
    {
        //TidalDex.com Factory
        IAmmFactory factory = IAmmFactory(
            0x907e8C7D471877b4742dA8aA53d257d0d565A47E
        );

        IERC20 czusd = IERC20(0xE68b79e51bf826534Ff37AA9CeE71a3842ee9c70);
        IERC20 czb = IERC20(0xD963b2236D227a0302E19F2f9595F424950dc186);
        IERC20 cl8y = IERC20(0x999311589cc1Ed0065AD9eD9702cB593FFc62ddF);
        IERC20 wbnb = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);

        isV2Pair[factory.createPair(address(this), address(czusd))] = true;
        isV2Pair[factory.createPair(address(this), address(czb))] = true;
        isV2Pair[factory.createPair(address(this), address(cl8y))] = true;
        isV2Pair[factory.createPair(address(this), address(wbnb))] = true;

        isExempt[owner()] = true;
        isExempt[address(this)] = true;
        isExempt[address(0)] = true;
        isExempt[taxReceiver] = true;

        _mint(owner(), 1_000_000 ether);
    }

    /// @notice Internal function to handle token transfers with tax and balance checks
    /// @dev Overrides ERC20's _update to implement sell tax and max balance restrictions
    /// @param from The sender's address
    /// @param to The recipient's address
    /// @param value The amount of tokens to transfer
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        if (isExempt[from] || isExempt[to] || value == 0) {
            //Skip all checks for exempt addresses
            super._update(from, to, value);
            return;
        }

        if (!tradingOpen()) {
            revert TradingNotOpen();
        }

        if (isV2Pair[from]) {
            // is a buy
            uint256 buyTax;
            if (block.timestamp - tradingOpenTime <= ANTI_SNIPE_DURATION) {
                // trading open during anti-snipe duration
                buyTax = (value * ANTI_SNIPE_TAX) / 10_000;
            } else {
                // trading open for more than anti-snipe duration
                buyTax = (value * buyTaxBasis) / 10_000;
            }
            super._update(from, to, value);
            //send tax from buyer, not from lp pair
            super._update(to, taxReceiver, buyTax);
        } else if (isV2Pair[to]) {
            // is a sell
            uint256 tax;
            if (block.timestamp - tradingOpenTime <= ANTI_SNIPE_DURATION) {
                // trading open during anti-snipe duration
                tax = (value * ANTI_SNIPE_TAX) / 10_000;
            } else {
                // trading open for more than anti-snipe duration
                tax = (value * sellTaxBasis) / 10_000;
            }
            super._update(from, to, value - tax);
            //send tax from seller, not from lp pair
            super._update(from, taxReceiver, tax);
        } else {
            // is a transfer
            //Default behavior for mints, burns, transfers
            super._update(from, to, value);
        }

        _revertIfStandardWalletAndOverMaxHolding(to);
    }

    /// @notice Checks if trading is currently open
    /// @return bool Returns true if current timestamp is greater than or equal to tradingOpenTime
    function tradingOpen() public view returns (bool) {
        if (tradingOpenTime == 0) {
            return false;
        }
        return (block.timestamp >= tradingOpenTime);
    }

    /// @notice Increases the maximum wallet holding limit to value
    /// @dev Can only be called by the owner and only if current maxBalance is less than value
    /// @param _value The new maximum wallet holding limit
    function ownerSetMaxWalletTo(uint256 _value) external onlyOwner {
        // Can only increase maxBalance.
        if (maxBalance >= _value) {
            revert OverMax(_value, maxBalance);
        }
        uint256 oldMaxBalance = maxBalance;
        maxBalance = _value;
        emit MaxBalanceUpdated(oldMaxBalance, maxBalance);
    }

    /// @notice Removes the maximum wallet holding limit
    /// @dev Can only be called by the owner, sets maxBalance to maximum uint256 value
    function ownerSetMaxWalletToMax() external onlyOwner {
        uint256 oldMaxBalance = maxBalance;
        maxBalance = type(uint256).max;
        emit MaxBalanceUpdated(oldMaxBalance, maxBalance);
    }

    /// @notice Updates the sell tax
    /// @dev Can only be called by the owner and cannot go above the tax cap
    /// @param _value The new sell tax
    function ownerSetSellTaxTo(uint256 _value) external onlyOwner {
        // Canot go above tax cap
        if (_value >= TAX_CAP) {
            revert OverMax(_value, TAX_CAP);
        }
        uint256 oldSellTaxBasis = sellTaxBasis;
        sellTaxBasis = _value;
        emit SellTaxBasisUpdated(oldSellTaxBasis, sellTaxBasis);
    }

    /// @notice Updates the buy tax
    /// @dev Can only be called by the owner and cannot go above the tax cap
    /// @param _value The new buy tax
    function ownerSetBuyTaxTo(uint256 _value) external onlyOwner {
        // Canot go above tax cap
        if (_value >= TAX_CAP) {
            revert OverMax(_value, TAX_CAP);
        }
        uint256 oldBuyTaxBasis = buyTaxBasis;
        buyTaxBasis = _value;
        emit BuyTaxBasisUpdated(oldBuyTaxBasis, buyTaxBasis);
    }

    /// @notice Allows the owner to rescue any ERC20 tokens accidentally sent to the contract
    /// @dev Can only be called by the owner
    /// @param _token The ERC20 token contract to rescue
    function ownerRescueTokens(IERC20 _token) external onlyOwner {
        _token.transfer(msg.sender, _token.balanceOf(address(this)));
    }

    /// @notice Allows the owner to open trading immediately
    /// @dev Can only be called by the owner
    function ownerOpenTradingNow() external onlyOwner {
        if (tradingOpen()) {
            revert TradingAlreadyOpen();
        }
        tradingOpenTime = block.timestamp;
    }

    /// @notice Allows the owner to set the trading open time
    /// @dev Can be used to instantly open trading, or set a future time
    /// @dev Cannot be used to close trading
    /// @dev Can only be called by the owner
    /// @param to The timestamp when trading becomes enabled
    function ownerSetTradingOpenTime(uint256 to) external onlyOwner {
        // Can only set the trading open time if its not currently open.
        if (tradingOpen()) {
            revert TradingAlreadyOpen();
        }
        tradingOpenTime = to;
    }

    /// @notice Allows the owner to set the tax receiver
    /// @dev Can only be called by the owner
    /// @param _value The new tax receiver
    function ownerSetTaxReceiver(address _value) external onlyOwner {
        address oldTaxReceiver = taxReceiver;
        taxReceiver = _value;
        emit TaxReceiverUpdated(oldTaxReceiver, taxReceiver);
    }

    /// @notice Exempt a wallet from the max balance check, anti-snipe, and sell/buy tax
    /// @dev Can only be called by the owner
    /// @param wallet The address to exempt
    function ownerExemptWallet(address wallet) external onlyOwner {
        isExempt[wallet] = true;
    }

    /// @notice Un-exempt a wallet from the max balance check, anti-snipe, and sell/buy tax
    /// @dev Can only be called by the owner
    /// @param wallet The address to un-exempt
    function ownerUnExemptWallet(address wallet) external onlyOwner {
        isExempt[wallet] = false;
    }

    /// @notice Add a wallet to the v2Pair list
    /// @dev Can only be called by the owner
    /// @param v2Pair The address to add to the v2Pair list
    function ownerAddV2Pair(address v2Pair) external onlyOwner {
        isV2Pair[v2Pair] = true;
    }

    /// @notice Internal function to check if a wallet exceeds maximum holding limit
    /// @dev Reverts if the wallet is not exempt and balance exceeds maxBalance
    /// @param wallet The address to check the balance for
    function _revertIfStandardWalletAndOverMaxHolding(
        address wallet
    ) internal view {
        if (
            !isV2Pair[wallet] &&
            !isExempt[wallet] &&
            balanceOf(wallet) > maxBalance
        ) {
            revert OverMax(balanceOf(wallet), maxBalance);
        }
    }
}
