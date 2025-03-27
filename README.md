# A$$ETS Token

A$$ETS is an ERC20 token contract with advanced features including tax mechanics, anti-snipe protection, and maximum wallet balance restrictions. The contract is built on the BNB Chain and integrates with TidalDex.com for liquidity.

## Features

- **Tax System**

  - Configurable buy and sell taxes
  - Tax cap of 20,000 tokens
  - Default buy tax: 1.00%
  - Default sell tax: 10.00%
  - Tax receiver address can be updated by owner

- **Anti-Snipe Protection**

  - 50% tax on buys during first 60 seconds of trading
  - Helps prevent front-running and sniping

- **Maximum Wallet Balance**

  - Default maximum balance: 30,000 tokens
  - Can only be increased, not decreased
  - Option to remove maximum balance limit entirely

- **Trading Controls**

  - Trading can be opened immediately or scheduled for future
  - Once trading is opened, it cannot be closed
  - Trading must be explicitly opened by owner

- **Exempt Addresses**
  - Owner can exempt addresses from:
    - Maximum balance restrictions
    - Anti-snipe protection
    - Buy/sell taxes

## Technical Details

- Built with Solidity ^0.8.23
- Implements OpenZeppelin contracts:
  - ERC20
  - ERC20Burnable
  - ERC20Permit
  - Ownable
  - SafeERC20

## Initial Setup

The contract is initialized with:

- Token Name: "A$$ETS"
- Token Symbol: "A$$ETS"
- Initial Supply: 1,000,000 tokens
- Initial Pairs on TidalDex.com:
  - A$$ETS/CZUSD
  - A$$ETS/CZB
  - A$$ETS/CL8Y
  - A$$ETS/WBNB

## Owner Functions

- `ownerSetMaxWalletTo(uint256 _value)`: Increase maximum wallet balance
- `ownerSetMaxWalletToMax()`: Remove maximum wallet balance limit
- `ownerSetSellTaxTo(uint256 _value)`: Update sell tax (cannot exceed cap)
- `ownerSetBuyTaxTo(uint256 _value)`: Update buy tax (cannot exceed cap)
- `ownerOpenTradingNow()`: Open trading immediately
- `ownerSetTradingOpenTime(uint256 to)`: Schedule trading to open at specific time
- `ownerSetTaxReceiver(address _value)`: Update tax receiver address
- `ownerExemptWallet(address wallet)`: Exempt address from restrictions
- `ownerUnExemptWallet(address wallet)`: Remove address exemption
- `ownerAddV2Pair(address v2Pair)`: Add new trading pair
- `ownerRescueTokens(IERC20 _token)`: Rescue ERC20 tokens sent to contract

## Security Features

- Trading must be explicitly opened
- Maximum wallet balance can only be increased
- Sell tax cannot be increased once reduced
- Trading cannot be closed once opened
- Owner can rescue tokens accidentally sent to contract

## License

GPL-3.0
