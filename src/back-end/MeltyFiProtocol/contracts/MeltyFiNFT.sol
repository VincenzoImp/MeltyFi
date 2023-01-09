// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

/// ChocoChip.sol is the governance token of the MeltyFi protocol
import "./ChocoChip.sol";
/// LogoCollection.sol is the meme token of the MeltyFi protocol
import "./LogoCollection.sol";
/// MeltyFiDAO.sol is the governance contract of the MeltyFi protocol
import "./MeltyFiDAO.sol";
/// VRFv2Consumer.sol is a contract that provides functionality for verifying proof of work
import "./VRFv2Consumer.sol";
/// IERC721.sol is an interface that defines the required methods for an ERC721 contract
import "@openzeppelin/contracts/token/ERC721/IERC721.sol"; 
/// IERC721Receiver.sol is an interface that defines methods for receiving ERC721 tokens
import"@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
/// ERC1155Supply.sol is a contract that extends the ERC1155 contract and provides functionality for managing the supply of ERC1155 tokens
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
/// AutomationBase.sol is a contract that provides basic functionality for integration with Chainlink, a platform for creating connections between smart contracts and external services
import "@chainlink/contracts/src/v0.8/AutomationBase.sol";
/// AutomationCompatibleInterface.sol is an interface that defines the required methods for being compatible with the Chainlink platform and using its automation functionality
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
/// Address library provides utilities for working with addresses
import "@openzeppelin/contracts/utils/Address.sol"; 
/// EnumerableSet library provides a data structure for storing and iterating over sets of values
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol"; 

/**
 * @title MeltyFiNFT
 * @author MeltyFi Team
 * @notice MeltyFiNFT is the contract that run the protocol of the MeltyFi platform.
 *         It manages the creation, cancellation and conclusion of lotteries, as well as the
 *         sale and refund of WonkaBars for each lottery, and also reward good users with ChocoChips.
 *         The contract allows users to create a lottery by choosing their NFT to put as lottery prize,
 *         setting an expiration date and defining a price in Ether for each WonkaBar sold.
 *         When a lottery is created, the contract will be able to mint a fixed amount of WonkaBars
 *         (setted by lottery owner) for the lottery. These WonkaBars are sold to users interested
 *         in participating in the lottery and money raised are sent to the lottery owner (less some fees).
 *         Once the expiration date is reached, the contract selects a random WonkaBar
 *         holder as the winner, who receives the prize NFT. Plus every wonkabar holder is rewarded
 *         with ChocoCips. If the lottery is cancelled by the owner beafore the expiration date,
 *         the contract refunds WonkaBars holders with Ether of the lottery owners. Plus every
 *         wonkabar holder is rewarded with ChocoCips.
 */
contract MeltyFiNFT is IERC721Receiver, ERC1155Supply, AutomationBase, AutomationCompatibleInterface {

    /// Data type representing the possible states of a lottery
    enum lotteryState {
        ACTIVE,
        CANCELLED,
        CONCLUDED,
        TRASHED
    }

    /// Struct for storing the information of a lottery
    struct Lottery {
        /// Expiration date of the lottery
        uint256 expirationDate;
        /// ID of the lottery
        uint256 id;
        /// Owner of the lottery
        address owner;
        /// Prize NFT contract of the lottery
        IERC721 prizeContract;
        /// Prize NFT token ID of the lottery
        uint256 prizeTokenId;
        /// State of the lottery
        lotteryState state;
        /// Winner of the lottery
        address winner;
        /// Number of WonkaBars sold for the lottery
        uint256 wonkaBarsSold;
        /// Maximum supply of WonkaBars for the lottery
        uint256 wonkaBarsMaxSupply;
        /// Price of each WonkaBar for the lottery, in wei
        uint256 wonkaBarPrice;
    }

    /// Using Address for address type
    using Address for address;
    /// Using EnumerableSet for EnumerableSet.AddressSet type
    using EnumerableSet for EnumerableSet.AddressSet;
    /// Using EnumerableSet for EnumerableSet.UintSet type
    using EnumerableSet for EnumerableSet.UintSet;

    /// Instance of the ChocoChip contract
    ChocoChip internal immutable _contractChocoChip;
    /// Instance of the LogoCollection contract
    LogoCollection internal immutable _contractLogoCollection;
    /// Instance of the MeltyFiDAO contract
    MeltyFiDAO internal immutable _contractMeltyFiDAO;
    /// Instance of the VRFv2Consumer contract
    VRFv2Consumer internal immutable _contractVRFv2Consumer;

    /// Amount of ChocoChips per Ether
    uint256 internal immutable _amountChocoChipPerEther;
    /// Percentage of royalties to be paid to the MeltyFiDAO
    uint256 internal immutable _royaltyDAOPercentage;
    /// Upper limit wonkabar balance percentage for a single address for a single lottery
    uint256 internal immutable _upperLimitBalanceOfPercentage;
    /// Upper limit wonkabar supply for a single lottery
    uint256 internal immutable _upperLimitMaxSupply;

    /// Total number of lotteries created.
    uint256 internal _totalLotteriesCreated;

    /// maps a unique lottery ID to a "Lottery" object containing information about the lottery itself
    mapping(
        uint256 => Lottery
    ) internal _lotteryIdToLottery;

    /// maps the address of a lottery owner to a set of lottery IDs that they own
    mapping(
        address => EnumerableSet.UintSet
    ) internal _lotteryOwnerToLotteryIds;

    /// maps the address of a WonkaBar holder to a set of lottery IDs for which they have purchased a ticket
    mapping(
        address => EnumerableSet.UintSet
    ) internal _wonkaBarHolderToLotteryIds;

    /// maps a lottery ID to a set of WonkaBar holder addresses that have purchased a ticket for that lottery
    mapping(
        uint256 => EnumerableSet.AddressSet
    ) internal _lotteryIdToWonkaBarHolders;

    /// set that stores the IDs of all active lotteries
    EnumerableSet.UintSet internal _activeLotteryIds;

    /**
     * @notice Creates a new instance of the MeltyFiNFT contract.
     *
     * @dev Raises error if the address of `contractChocoChip` is not equal to the token address of `contractMeltyFiDAO`.
     *      Raises error if the owner of `contractChocoChip` is not the current message sender.
     *      Raises error if the owner of `contractLogoCollection` is not the current message sender.
     *      Raises error if the owner of `contractVRFv2Consumer` is not the current message sender.
     *
     * @param contractChocoChip instance of the ChocoChip contract.
     * @param contractLogoCollection instance of the LogoCollection contract.
     * @param contractMeltyFiDAO instance of the MeltyFiDAO contract.
     */
    constructor(
        ChocoChip contractChocoChip,
        LogoCollection contractLogoCollection,
        MeltyFiDAO contractMeltyFiDAO,
        VRFv2Consumer contractVRFv2Consumer
    ) ERC1155("https://ipfs.io/ipfs/QmTiQsRBGcKyyipnRGVTu8dPfykM89QHn81KHX488cTtxa")
    {
        /// The ChocoChip contract and the MeltyFiDAO token must be the same contract
        require(
            address(contractChocoChip) == address(contractMeltyFiDAO.token()),
            "MeltyFiNFT: address of contractChocoChip is not equal to the token address of the contractMeltyFiDAO"
        );
        /// The caller must be the owner of the ChocoChip contract.
        require(
            contractChocoChip.owner() == _msgSender(), 
            "MeltyFiNFT: the owner of contractChocoChip is not the current message sender"
        );
        /// The caller must be the owner of the LogoCollection contract.
        require(
            contractLogoCollection.owner() == _msgSender(),
            "MeltyFiNFT: the owner of contractLogoCollection is not the current message sender"
        );
        /// The caller must be the owner of the VRFv2Consumer contract.
        require(
            contractVRFv2Consumer.owner() == _msgSender(), 
            "MeltyFiNFT: the owner of contractVRFv2Consumer is not the current message sender"
        );

        /// Initializing the immutable variables
        _contractChocoChip = contractChocoChip;
        _contractLogoCollection = contractLogoCollection;
        _contractMeltyFiDAO = contractMeltyFiDAO;
        _contractVRFv2Consumer = contractVRFv2Consumer;
        _amountChocoChipPerEther = 1000;
        _royaltyDAOPercentage = 5;
        _upperLimitBalanceOfPercentage = 25;
        _upperLimitMaxSupply = 100;
        _totalLotteriesCreated = 0;
    }

    /**
     * @notice Handles incoming ether payments.
     *
     * @dev This function is required for contracts that want to receive ether. 
     *      It is called automatically whenever ether is sent to the contract.
     */
    receive() external payable {
    }

    /**
     * @notice A function that is called when an ERC721 token is received by this contract.
     *
     * @param operator The address of the operator that is transferring the token.
     * @param from The address of the token owner.
     * @param tokenId The identifier of the token being transferred.
     * @param data Additional data associated with the token transfer.
     *
     * @return The four-byte selector of the `onERC721Received` function.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @notice An internal function that is called before a token transfer occurs.
     *
     * @dev This function is called by the `transfer()` and `safeTransfer()` functions
     *      of the `ERC1155Supply` contract to perform any necessary pre-transfer
     *      logic. It is marked as `internal` and `override` to ensure that it can
     *      only be called from within the contract and that it can be overridden
     *      by derived contracts.
     *
     * @param operator The address of the operator that is transferring the tokens.
     * @param from The address of the token owner.
     * @param to The address of the recipient of the tokens.
     * @param ids An array of token identifiers.
     * @param amounts An array of token amounts.
     * @param data Additional data associated with the token transfer.
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155Supply)
    {
        /// update _wonkaBarHolderToLotteryIds and _lotteryIdToWonkaBarHolders
        for (uint256 i=0; i<ids.length; i++) {
            if (amounts[i] != 0 && to != address(0)) {
                _wonkaBarHolderToLotteryIds[to].add(ids[i]);
                _lotteryIdToWonkaBarHolders[ids[i]].add(to);
            }
        }
        /// call the super function to perform any necessary pre-transfer logic
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    /**
     * @notice An internal function that is called after a token transfer occurs.
     *
     * @dev This function is called by the `transfer()` and `safeTransfer()` functions
     *      of the `ERC1155` contract to perform any necessary post-transfer logic.
     *      It is marked as `internal` and `override` to ensure that it can only be
     *      called from within the contract and that it can be overridden by derived
     *      contracts.
     *
     * @param operator The address of the operator that transferred the tokens.
     * @param from The address of the token owner.
     * @param to The address of the recipient of the tokens.
     * @param ids An array of token identifiers.
     * @param amounts An array of token amounts.
     * @param data Additional data associated with the token transfer.
     */
    function _afterTokenTransfer (
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155) 
    {
        /// update _wonkaBarHolderToLotteryIds and _lotteryIdToWonkaBarHolders
        for (uint256 i=0; i<ids.length; i++) {
            if (from != address(0) && balanceOf(from, ids[i]) == 0) {
                _wonkaBarHolderToLotteryIds[from].remove(ids[i]);
                _lotteryIdToWonkaBarHolders[ids[i]].remove(from);
            }
        }
        /// call the super function to perform any necessary post-transfer logic
        super._afterTokenTransfer (operator, from, to, ids, amounts, data);
    }

    /**
     * @notice Returns an array of the IDs of all active lotteries.
     *
     * @dev An active lottery is one that has not yet been cancelled or colcluded
     *      and is still selling tickets. This function returns an array of the 
     *      IDs of all such lotteries.
     *
     * @return An array of the IDs of all active lotteries.
     */
    function activeLotteryIds() public view returns(uint256[] memory )
    {
        // return the values of _activeLotteryIds
        return _activeLotteryIds.values();
    }

    /**
     * @notice Returns an array of the IDs of all lotteries owned by a given address.
     *
     * @param owner The address of the lottery owner.
     *
     * @return An array of the IDs of all lotteries owned by the given address.
     */
    function ownedLotteryIds(
        address owner
    ) public view returns(uint256[] memory )
    {
        /// return the values of _lotteryOwnerToLotteryIds[owner]
        return _lotteryOwnerToLotteryIds[owner].values();
    }

    /**
     * @notice Returns an array of the IDs of all lotteries in which a given address holds WonkaBars.
     *
     * @param holder The address of the WonkaBar holder.
     *
     * @return An array of the IDs of all lotteries in which the given address holds WonkaBars.
     */
    function holderInLotteryIds(
        address holder
    ) public view returns(uint256[] memory )
    {
        /// return the values of _wonkaBarHolderToLotteryIds[holder]
        return _wonkaBarHolderToLotteryIds[holder].values();
    }

    /**
     * @dev An internal function that returns the address of the ChocoChip contract.
     *
     * @return The address of the ChocoChip contract.
     */
    function _addressChocoChip() internal view returns (address) 
    {
        /// return the address of the ChocoChip contract
        return address(_contractChocoChip);
    }

    /**
     * @dev An internal function that returns the address of the LogoCollection contract.
     *
     * @return The address of the LogoCollection contract.
     */
    function _addressLogoCollection() internal view returns (address) 
    {
        /// return the address of the LogoCollection contract
        return address(_contractLogoCollection);
    }

    /**
     * @dev An internal function that returns the address of the MeltyFiDAO contract.
     *
     * @return The address of the MeltyFiDAO contract.
     */
    function _addressMeltyFiDAO() internal view returns (address) 
    {
        /// return the address of the MeltyFiDAO contract
        return address(_contractMeltyFiDAO);
    }

    /**
     * @dev An internal function that calculates the amount to refund to a given address for a given lottery.
     *      This function is called only if the lottery is cancelled. 
     *
     * @param lottery The lottery for which to calculate the refund amount.
     * @param addressToRefund The address to which the refund will be made.
     *
     * @return The amount to refund to the given address for the given lottery.
     */
    function _amountToRefund(
        Lottery memory lottery, 
        address addressToRefund
    ) internal view returns (uint256)
    {
        /// return the WonkaBar balance of the address in the given lottery multiplied by the price of WonkaBars in the lottery
        return balanceOf(addressToRefund, lottery.id) * lottery.wonkaBarPrice;
    }

    /**
     * @dev An internal function that calculates the amount to repay for a given lottery.
     *      This function is called only if the lottery is active. 
     *
     * @param lottery The lottery for which to calculate the amount to repay.
     *
     * @return The amount to repay for the given lottery.
     */
    function _amountToRepay(
        Lottery memory lottery
    ) internal pure returns (uint256)  
    {
        /// return the number of WonkaBars sold in the lottery multiplied by the price of WonkaBars in the lottery
        return lottery.wonkaBarsSold * lottery.wonkaBarPrice;
    }

    /**
     * @dev An internal function that mints a logo token to a given address.
     *
     * @param to The address to which the logo token will be minted.
     */
    function _mintLogo(
        address to
    ) internal
    {
        /// call the `mint()` function of the LogoCollection contract to mint a logo token to the given address
        _contractLogoCollection.mint(to, 0, 1, "");
    }   

    /**
     * @notice Returns the address of the ChocoChip contract.
     *
     * @return The address of the ChocoChip contract.
     */
    function addressChocoChip() public view returns (address) 
    {
        /// call the internal function to return the address of the ChocoChip contract
        return _addressChocoChip();
    }

    /**
     * @notice Returns the address of the LogoCollection contract.
     *
     * @return The address of the LogoCollection contract.
     */
    function addressLogoCollection() public view returns (address) 
    {
        /// call the internal function to return the address of the LogoCollection contract
        return _addressLogoCollection();
    }

    /**
     * @notice Returns the address of the MeltyFiDAO contract.
     *
     * @return The address of the MeltyFiDAO contract.
     */
    function addressMeltyFiDAO() public view returns (address) 
    {
        /// call the internal function to return the address of the MeltyFiDAO contract
        return _addressMeltyFiDAO();
    }

    /**
     * @notice Returns the amount to refund to a given address for a given lottery.
     *
     * @param lotteryId The ID of the lottery for which to calculate the refund amount.
     * @param addressToRefund The address to which the refund will be made.
     *
     * @return The amount to refund to the given address for the given lottery. Returns 0 if the lottery is not cancelled.
     */
    function amountToRefund(
        uint256 lotteryId, 
        address addressToRefund
    ) public view returns (uint256)
    {
        /// retrieve the lottery with the given ID
        Lottery memory lottery = _lotteryIdToLottery[lotteryId];
        /// if the lottery is not cancelled, return 0
        if (lottery.state != lotteryState.CANCELLED) {
            return 0;
        }
        /// otherwise, return the amount to refund calculated by the internal function
        return _amountToRefund(lottery, addressToRefund);
    }
    
    /**
     * @notice Returns the amount to repay for a given lottery.
     *
     * @param lotteryId The ID of the lottery for which to calculate the amount to repay.
     *
     * @return The amount to repay for the given lottery. Returns 0 if the lottery is not active.
     */
    function amountToRepay(
        uint256 lotteryId
    ) public view returns (uint256)
    {
        /// retrieve the lottery with the given ID
        Lottery memory lottery = _lotteryIdToLottery[lotteryId];
        /// if the lottery is not active, return 0
        if (lottery.state != lotteryState.ACTIVE) {
            return 0;
        }
        /// otherwise, return the amount to repay calculated by the internal function
        return _amountToRepay(lottery);
    }

    /**
     * @notice Returns the expiration date of a given lottery.
     *
     * @param lotteryId The ID of the lottery for which to retrieve the expiration date.
     *
     * @return The expiration date of the given lottery.
     */
    function getLotteryExpirationDate(
        uint256 lotteryId
    ) public view returns (uint256) 
    {
        /// return the expiration date of the lottery with the given ID
        return _lotteryIdToLottery[lotteryId].expirationDate;
    }

    /**
     * @notice Returns the owner of a given lottery.
     *
     * @param lotteryId The ID of the lottery for which to retrieve the owner.
     *
     * @return The owner of the given lottery.
     */
    function getLotteryOwner(
        uint256 lotteryId
    ) public view returns (address) 
    {
        /// return the owner of the lottery with the given ID
        return _lotteryIdToLottery[lotteryId].owner;
    }

    /**
     * @notice Returns the address of the prize contract for a given lottery.
     *
     * @param lotteryId The ID of the lottery for which to retrieve the prize contract address.
     *
     * @return The address of the prize contract for the given lottery.
     */
    function getLotteryPrizeContract(
        uint256 lotteryId
    ) public view returns (address) 
    {
        /// return the address of the prize contract for the lottery with the given ID
        return address(_lotteryIdToLottery[lotteryId].prizeContract);
    }

    /**
     * @notice Returns the token ID of the prize for a given lottery.
     *
     * @param lotteryId The ID of the lottery for which to retrieve the prize token ID.
     *
     * @return The token ID of the prize for the given lottery.
     */
    function getLotteryPrizeTokenId(
        uint256 lotteryId
    ) public view returns (uint256) 
    {
        /// return the token ID of the prize for the lottery with the given ID
        return _lotteryIdToLottery[lotteryId].prizeTokenId;
    }

    /**
     * @notice Returns the state of a given lottery.
     *
     * @param lotteryId The ID of the lottery for which to retrieve the state.
     *
     * @return The state of the given lottery.
     */
    function getLotteryState(
        uint256 lotteryId
    ) public view returns (lotteryState) 
    {
        /// return the state of the lottery with the given ID
        return _lotteryIdToLottery[lotteryId].state;
    }

    /**
     * @notice Returns the winner of a given lottery.
     *
     * @param lotteryId The ID of the lottery for which to retrieve the winner.
     *
     * @return The winner of the given lottery.
     */
    function getWinner(
        uint256 lotteryId
    ) public view returns (address) 
    {
        /// return the winner of the lottery with the given ID
        return _lotteryIdToLottery[lotteryId].winner;
    }

    /**
     * @notice Returns the number of Wonka Bars sold in a given lottery.
     *
     * @param lotteryId The ID of the lottery for which to retrieve the number of Wonka Bars sold.
     *
     * @return The number of Wonka Bars sold in the given lottery.
     */
    function getLotteryWonkaBarsSold(
        uint256 lotteryId
    ) public view returns (uint256) 
    {
        /// return the number of Wonka Bars sold in the lottery with the given ID
        return _lotteryIdToLottery[lotteryId].wonkaBarsSold;
    }

    /**
     * @notice Returns the maximum number of Wonka Bars for sale in a given lottery.
     *
     * @param lotteryId The ID of the lottery for which to retrieve the maximum number of Wonka Bars for sale.
     *
     * @return The maximum number of Wonka Bars for sale in the given lottery.
     */
    function getLotteryWonkaBarsMaxSupply(
        uint256 lotteryId
    ) public view returns (uint256) 
    {
        /// return the maximum number of Wonka Bars for sale in the lottery with the given ID
        return _lotteryIdToLottery[lotteryId].wonkaBarsMaxSupply;
    }

    /**
     * @notice Returns the price of a Wonka Bar in a given lottery.
     *
     * @param lotteryId The ID of the lottery for which to retrieve the price of a Wonka Bar.
     *
     * @return The price of a Wonka Bar in the given lottery.
     */
    function getLotteryWonkaBarPrice(
        uint256 lotteryId
    ) public view returns (uint256) 
    {
        /// return the price of a Wonka Bar in the lottery with the given ID
        return _lotteryIdToLottery[lotteryId].wonkaBarPrice;
    }

    function mintLogo(
        address to
    ) public 
    {
        _mintLogo(to);
    }

    /**
     * Creates a new lottery.
     *
     * @param duration expiration date of the lottery.
     * @param prizeContract address of the prize NFT contract.
     * @param prizeTokenId ID of the prize NFT token.
     * @param wonkaBarPrice price of each WonkaBar, in ChocoChips.
     * @param wonkaBarsMaxSupply maximum supply of WonkaBars for the lottery.
     * @return lotteryId of the newly created lottery.
     */
    function createLottery(
        uint256 duration,
        IERC721 prizeContract,
        uint256 prizeTokenId,
        uint256 wonkaBarPrice,
        uint256 wonkaBarsMaxSupply
    ) public returns (uint256) 
    {
        /*
        require(
            prizeContract.ownerOf(prizeTokenId) == _msgSender(), 
            ""
        );
        */
        require(
            wonkaBarsMaxSupply <= _upperLimitMaxSupply,
            ""
        );
        require(
            (wonkaBarsMaxSupply * _upperLimitBalanceOfPercentage) / 100 >= 1, 
            ""
        );
        
        prizeContract.safeTransferFrom(
            _msgSender(),
            address(this),
            prizeTokenId
        );

        uint256 lotteryId = _totalLotteriesCreated;

        /// Creating the lottery.
        _lotteryIdToLottery[lotteryId] = Lottery(
            block.timestamp+duration,
            lotteryId,
            _msgSender(),
            prizeContract,
            prizeTokenId,
            lotteryState.ACTIVE,
            address(0),
            0,
            wonkaBarsMaxSupply,
            wonkaBarPrice
        );

        /// manage after creating
        _totalLotteriesCreated += 1;
        _lotteryOwnerToLotteryIds[_msgSender()].add(lotteryId);
        _activeLotteryIds.add(lotteryId);

        return lotteryId;
    }

    /**
     * Buys WonkaBars for a lottery.
     *
     * @param lotteryId ID of the lottery.
     * @param amount amount of Ether paid for the WonkaBars.
     */
    function buyWonkaBars(
        uint256 lotteryId, 
        uint256 amount
    ) public payable
    {
        Lottery memory lottery = _lotteryIdToLottery[lotteryId];

        uint256 totalSpending = amount * lottery.wonkaBarPrice;

        /// The lottery must be active.
        require(
            block.timestamp < lottery.expirationDate,
            ""
        );
        /// The total supply of WonkaBars must not exceed the maximum supply allowed.
        require(
            lottery.wonkaBarsSold + amount <= lottery.wonkaBarsMaxSupply,
            ""
        );
        
        require(
            (
                ((balanceOf(_msgSender(), lotteryId) + amount + 1) * 100)
                / 
                lottery.wonkaBarsMaxSupply
            )
            <=
            _upperLimitBalanceOfPercentage,
            ""
        );
        
        require(
            msg.value >= totalSpending, 
            ""
        );

        uint256 valueToDAO = (totalSpending / 100) * _royaltyDAOPercentage;
        Address.sendValue(payable(_addressMeltyFiDAO()), valueToDAO);

        uint256 valueToLotteryOwner = totalSpending - valueToDAO;
        Address.sendValue(payable(lottery.owner), valueToLotteryOwner);

        _mint(_msgSender(), lotteryId, amount, "");
        
        _lotteryIdToLottery[lotteryId].wonkaBarsSold += amount;

    }

    function repayLoan(uint256 lotteryId) public payable {
        
        Lottery memory lottery = _lotteryIdToLottery[lotteryId];

        uint256 totalPaying = _amountToRepay(lottery);

        require(
            lottery.owner == _msgSender(),
            ""
        );

        require(
            msg.value >= totalPaying, 
            ""
        );

        require(
            block.timestamp < lottery.expirationDate, 
            ""
        );

        _contractChocoChip.mint(
            _msgSender(),
            totalPaying * _amountChocoChipPerEther
        );

        lottery.prizeContract.safeTransferFrom(
            address(this),
            _msgSender(),
            lottery.prizeTokenId
        );
        
        /// manage after repaying
        _activeLotteryIds.remove(lotteryId);
        _lotteryIdToLottery[lotteryId].expirationDate = block.timestamp;
        if (totalSupply(lotteryId) == 0) {
            _lotteryIdToLottery[lotteryId].state = lotteryState.TRASHED;
        } else {
            _lotteryIdToLottery[lotteryId].state = lotteryState.CANCELLED;
        }

    }

    function meltWonkaBars(uint256 lotteryId, uint256 amount) public {
        
        Lottery memory lottery = _lotteryIdToLottery[lotteryId];

        uint256 totalRefunding = _amountToRefund(lottery, _msgSender());

        require(
            balanceOf(_msgSender(), lotteryId) >= amount,
            ""
        );

        if (block.timestamp >= lottery.expirationDate) { //qui puo' essere conclusa o  trashed e non vogliamo che sia trashed
            require(
                totalSupply(lotteryId) > 0,
                ""/// lotteria trashed
            );
        } else { //qui puo' essere attiva o cancellata e non vogliamo che sia attiva
            require(
                lottery.state == lotteryState.CANCELLED,
                ""///lotteria attiva
            );
        }

        _burn(_msgSender(), lotteryId, amount);

        _contractChocoChip.mint(
            _msgSender(),
            totalRefunding * _amountChocoChipPerEther
        );

        if (lottery.state == lotteryState.CANCELLED) {
            Address.sendValue(payable(_msgSender()), totalRefunding);
        }

        if (
            lottery.state == lotteryState.CONCLUDED 
            && 
            _msgSender() == lottery.winner
            &&
            IERC721(lottery.prizeContract).ownerOf(lottery.prizeTokenId) == address(this)
        ) {
            IERC721(lottery.prizeContract).safeTransferFrom(
                address(this), 
                _msgSender(), 
                lottery.prizeTokenId
            );
        }
        
        /// manage after melting
        if (totalSupply(lotteryId) == 0) {
            _lotteryIdToLottery[lotteryId].state = lotteryState.TRASHED;
        }

    }

    function drawWinner(
        uint256 lotteryId
    ) internal 
    {
        Lottery memory lottery = _lotteryIdToLottery[lotteryId];

        require(
            lottery.state == lotteryState.ACTIVE
            &&
            lottery.expirationDate < block.timestamp,
            ""
        );
        
        _activeLotteryIds.remove(lotteryId);
        uint256 numberOfWonkaBars = totalSupply(lotteryId);

        if (numberOfWonkaBars == 0) {
            lottery.prizeContract.safeTransferFrom(
                address(this),
                lottery.owner,
                lottery.prizeTokenId
            );
            _lotteryIdToLottery[lotteryId].state = lotteryState.TRASHED;
        } else {
            EnumerableSet.AddressSet storage wonkaBarHolders = _lotteryIdToWonkaBarHolders[lotteryId];
            uint256 numberOfWonkaBarHolders = wonkaBarHolders.length();
            uint256 requestId = _contractVRFv2Consumer.requestRandomWords();
            (bool fulfilled, uint256[] memory randomWords) = _contractVRFv2Consumer.getRequestStatus(requestId);
            require(fulfilled, "");
            uint256 winnerIndex = (randomWords[0]%numberOfWonkaBars)+1;
            uint256 totalizer = 0; 
            address winner;
            
            for (uint256 i=0; i<numberOfWonkaBarHolders; i++) {
                address holder = wonkaBarHolders.at(i);
                totalizer += balanceOf(holder, lotteryId);
                if (winnerIndex <= totalizer) {
                    winner = holder;
                    break;
                }
            }
            _lotteryIdToLottery[lotteryId].winner = winner;
            _lotteryIdToLottery[lotteryId].state = lotteryState.CONCLUDED;
        }
        
    }

    function checkUpkeep(
        bytes calldata /*checkData*/
    ) external view cannotExecute returns (bool upkeepNeeded, bytes memory performData) 
    {
        uint256 numberOfActiveLottery = _activeLotteryIds.length();
        for (uint256 i=0; i<numberOfActiveLottery; i++) {
            uint256 lotteryId = _activeLotteryIds.at(i);
            if (_lotteryIdToLottery[lotteryId].expirationDate < block.timestamp) {
                return (true, abi.encode(lotteryId));
            }
        }
        return (false, "");
    }

    function performUpkeep(bytes calldata performData) external {
        uint256 lotteryId = abi.decode(performData, (uint256));
        drawWinner(lotteryId);
    }


}

/**
 * @dev
 * il lender riceve 1 choc pari al numero di finney spesi in ticket
 * il bowworare riceve 1 choc pari al numero di finney spesi in interessi
 *
 */
