# Sunder Contracts

## Description

Sunder Protocol provides decentralized vault services with fungible tokens on Ethereum. It allows the market set coverage prices as opposed to using bonding curves. The process starts when market makers (MMs) deposit collateral to split tokens. MMs will receive two types of fungible DAO tokens and Earning tokens in exchange for their deposit. MMs can choose to sell the fungible token(s) to earn premiums, or provide liquidity in DEX pools with the fungible token(s) and earn fees. Governance seekers can then buy the DAO tokens to vote. Yield seekers can buy earning tokens to earn profit. For more info, you can follow us here: https://sunderfinance.medium.com/.

Mint and Redeem correspond to ConvController, DToken and EToken contracts.
Liquidity Rewards correspond to MasterChef contract.
Earn Yield corresponds to SVault contract.

All contracts do not use the delegatecall method. The strategy contract and vote contract can be upgraded on chain.
Strategy contract can be upgraded with Controller contract. 
Vote contract can be upgraded with VoteController contract.


## Contract Functions
Still under development.

## License
Sunder contracts and all other utilities are licensed under [Apache 2.0](LICENSE).

## Contact
If you want any further information, feel free to contact us at **contact@sunder.finance** :) ...
