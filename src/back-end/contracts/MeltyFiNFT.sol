// SPDX-License-Identifier: MIT

/**
 * MeltyFiNFT is the contract that run the protocol of the MeltyFi platform.
 * It manages the creation, cancellation and conclusion of lotteries, as well as the
 * sale and refund of WonkaBars for each lottery, and also reward good users with ChocoChips.
 * The contract allows users to create a lottery by choosing their NFT to put as lottery prize,
 * setting an expiration date and defining a price in Ether for each WonkaBar sold.
 * When a lottery is created, the contract will be able to mint a fixed amount of WonkaBars
 * (setted by lottery owner) for the lottery. These WonkaBars are sold to users interested
 * in participating in the lottery and money raised are sent to the lottery owner (less some fees).
 * Once the expiration date is reached, the contract selects a random WonkaBar
 * holder as the winner, who receives the prize NFT. Plus every wonkabar holder is rewarded
 * with ChocoCips. If the lottery is cancelled by the owner beafore the expiration date,
 * the contract refunds WonkaBars holders with Ether of the lottery owners. Plus every
 * wonkabar holder is rewarded with ChocoCips.
 * @author MeltyFi Team
 * @version 0.1.0
 */

pragma solidity ^0.8.9;

/// ChocoChip contract is the governance token of the MeltyFi platform.
import "./ChocoChip.sol"; 
/// MeltyFiDAO contract is the governance contract of the MeltyFi platform.
import "./MeltyFiDAO.sol";
/// WonkaBar contract is the utility token of the MeltyFi platform.
import "./WonkaBar.sol"; 
/// IERC721 interface defines the required methods for an ERC721 contract.
import "@openzeppelin/contracts/token/ERC721/IERC721.sol"; 
/// Address library provides utilities for working with addresses.
import "@openzeppelin/contracts/utils/Address.sol"; 
/// EnumerableSet library provides a data structure for storing and iterating over sets of values.
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol"; 

contract MeltyFiNFT is Context {

    enum lotteryState {
        ACTIVE,
        CANCELLED,
        CONCLUDED,
        TRASHED
    }

    enum classInfo {
        OWNER,
        PRIZECONTRACT,
        WONKABARHOLDER
    }

    /// Using Address for address type.
    using Address for address;
    /// Using EnumerableSet for EnumerableSet.AddressSet type.
    using EnumerableSet for EnumerableSet.AddressSet;
    /// Using EnumerableSet for EnumerableSet.UintSet type.
    using EnumerableSet for EnumerableSet.UintSet;

    /// Instance of the ChocoChip contract.
    ChocoChip internal immutable _contractChocoChip;
    /// Instance of the MeltyFiDAO contract.
    MeltyFiDAO internal immutable _contractMeltyFiDAO;
    /// Instance of the WonkaBar contract.
    WonkaBar internal immutable _contractWonkaBar;
    
    /// Amount of ChocoChips per Ether.
    uint256 internal immutable _amountChocoChipPerEther;
    /// Percentage of royalties to be paid to the MeltyFiDAO.
    uint256 internal immutable _royaltyDAOPercentage;
    /// Upper limit percentage of the value of the prize NFT.
    uint256 internal immutable _upperLimitPercentage;

    /// Struct for storing the information of a lottery.
    struct Lottery {
        /// Expiration date of the lottery.
        uint256 expirationDate;
        /// ID of the lottery.
        uint256 id;
        /// Owner of the lottery.
        address owner;
        /// Prize NFT contract of the lottery.
        IERC721 prizeContract;
        /// Prize NFT token ID of the lottery.
        uint256 prizeTokenId;
        /// State of the lottery.
        lotteryState state;
        /// Winner of the lottery.
        address winner;
        /// Number of WonkaBars sold for the lottery.
        uint256 wonkaBarsSold;
        /// Maximum supply of WonkaBars for the lottery.
        uint256 wonkaBarsMaxSupply;
        /// Price of each WonkaBar for the lottery, in ChocoChips
        uint256 wonkaBarPrice;
    }

    /// Total number of lotteries created.
    uint256 internal _totalLotteriesCreated;

    mapping(
        uint256 => Lottery
    ) internal _lotteryIdToLottery;

    mapping(
        address => EnumerableSet.UintSet
    ) internal _lotteryOwnerToLotteryIds;

    mapping(
        address => EnumerableSet.UintSet
    ) internal _wonkaBarHolderToLotteryIds;

    EnumerableSet.UintSet _activeLotteryIds;

    /**
     * Constructor of the MeltyFiNFT contract.
     *
     * @param contractChocoChip instance of the ChocoChip contract.
     * @param contractWonkaBar instance of the WonkaBar contract.
     * @param contractMeltyFiDAO instance of the MeltyFiDAO contract.
     */
    constructor(
        ChocoChip contractChocoChip,
        MeltyFiDAO contractMeltyFiDAO,
        WonkaBar contractWonkaBar
    ) 
    {
        /// The ChocoChip contract and the MeltyFiDAO token must be the same contract.
        require(
            address(contractChocoChip) == address(contractMeltyFiDAO.token()),
            ""
        );
        /// The caller must be the owner of the ChocoChip contract.
        require(contractChocoChip.owner() == _msgSender(), "");

        /// Initializing the instance variables.
        _contractChocoChip = contractChocoChip;
        _contractMeltyFiDAO = contractMeltyFiDAO;
        _contractWonkaBar = contractWonkaBar;

        _amountChocoChipPerEther = 1000;
        _royaltyDAOPercentage = 5;
        _upperLimitPercentage = 25;
        _totalLotteriesCreated = 0;
    }

    /**
     * Returns the address of the ChocoChip contract.
     *
     * @return address of the ChocoChip contract.
     */
    function _addressChocoChip() internal view virtual returns (address) 
    {
        return address(_contractChocoChip);
    }

    /**
     * Returns the address of the MeltyFiDAO contract.
     *
     * @return address of the MeltyFiDAO contract.
     */
    function _addressMeltyFiDAO() internal view virtual returns (address) 
    {
        return address(_contractMeltyFiDAO);
    }

    /**
     * Returns the address of the WonkaBar contract.
     *
     * @return address of the WonkaBar contract.
     */
    function _addressWonkaBar() internal view virtual returns (address) 
    {
        return address(_contractWonkaBar);
    }

    /**
     * Calculates the amount to be refunded to a user when a lottery is cancelled or has no WonkaBars sold.
     * The amount is equal to the number of ChocoChips the user paid for the WonkaBars minus the royalties to be paid to the MeltyFiDAO.
     *
     * @param lottery information of the lottery.
     * @param addressToRefund address of the user to be refunded.
     * @return amount to be refunded.
     */
    function _amountToRefund(
        Lottery memory lottery, 
        address addressToRefund
    ) internal view virtual returns (uint256)
    {
        return _contractWonkaBar.balanceOf(addressToRefund, lottery.id) * lottery.wonkaBarPrice;
    }

    /**
     * Calculates the amount to be repaid to a user when a lottery is cancelled or has no WonkaBars sold.
     * The amount is equal to the number of WonkaBars the user bought multiplied by the price of each WonkaBar.
     *
     * @param lottery information of the lottery.
     * @return amount to be repaid.
     */
    function _amountToRepay(
        Lottery memory lottery
    ) internal view virtual returns (uint256)  
    {
        return lottery.wonkaBarsSold * lottery.wonkaBarPrice;
    }

    function _checkIfToTrash(
        Lottery memory lottery
    ) internal virtual
    {
        if (_isToTrashLottery(lottery)) {
            _changeLotteryState(lottery, lotteryState.TRASHED);
        }
    }

    function _changeLotteryState(
        Lottery memory lottery,
        lotteryState newLotteryState
    ) internal virtual 
    {
        require(
            (
                lottery.state == lotteryState.ACTIVE 
                &&
                (
                    newLotteryState == lotteryState.CANCELLED 
                    ||
                    newLotteryState == lotteryState.CONCLUDED
                )
            ) 
            ||
            (
                (
                    lottery.state == lotteryState.CANCELLED 
                    ||
                    lottery.state == lotteryState.CONCLUDED
                ) 
                &&
                newLotteryState == lotteryState.TRASHED
            )
        );
        /*
        (
            _lotteryStateToLotteryIds[lottery.state],
            _lotteryStateToLotteryIds[newLotteryState]
        ) = (
            _lotteryStateToLotteryIds[newLotteryState],
            _lotteryStateToLotteryIds[lottery.state]
        );

        _lotteryStateToClassInfoToLotteryAddressTolotteryIds

        (
            _lotteryStateToClassInfoToAddresses[lottery.state],
            _lotteryStateToClassInfoToAddresses[newLotteryState]
        ) = (
            _lotteryStateToClassInfoToAddresses[newLotteryState],
            _lotteryStateToClassInfoToAddresses[lottery.state]
        );
        */
        Lottery storage sLottery = _lotteryIdToLottery[lottery.id];
        sLottery.state = newLotteryState;
    }

    function _isToTrashLottery(
        Lottery memory lottery
    ) internal view virtual returns (bool)
    {
        uint256 supplyWonkaBars = _contractWonkaBar.totalSupply(lottery.id);
        return 
        (
            (
                lottery.state == lotteryState.CANCELLED 
                ||
                lottery.state == lotteryState.CONCLUDED
            ) 
            &&
            supplyWonkaBars == 0
        );
    }

    function _storeNewLottery(Lottery memory lottery) internal virtual 
    {
        _lotteryIdToLottery[lottery.id] = lottery;

        _lotteryStateToLotteryIds[
            lottery.state].add(lottery.id);

        _lotteryStateToClassInfoToLotteryAddressTolotteryIds[
            lottery.state][
                classInfo.OWNER][
                    _msgSender()].add(lottery.id);

        _lotteryStateToClassInfoToLotteryAddressTolotteryIds[
            lottery.state][
                classInfo.PRIZECONTRACT][
                    address(lottery.prizeContract)].add(lottery.id);

        _lotteryStateToClassInfoToAddresses[
            lottery.state][
                classInfo.OWNER].add(lottery.owner);

        _lotteryStateToClassInfoToAddresses[
            lottery.state][
                classInfo.PRIZECONTRACT].add(address(lottery.prizeContract));
    }

    function addressChocoChip() public view virtual returns (address) 
    {
        return _addressChocoChip();
    }

    function addressMeltyFiDAO() public view virtual returns (address) 
    {
        return _addressMeltyFiDAO();
    }

    function addressWonkaBar() public view virtual returns (address) 
    {
        return _addressWonkaBar();
    }

    function amountToRefund(
        uint256 lotteryId, 
        address addressToRefund
    ) public view virtual returns (uint256)
    {
        Lottery memory lottery = _lotteryIdToLottery[lotteryId];
        require(
            lottery.state == lotteryState.CANCELLED,
            ""
        );
        return _amountToRefund(lottery, addressToRefund);
    }
    
    function amountToRepay(
        uint256 lotteryId
    ) public view virtual returns (uint256)
    {
        Lottery memory lottery = _lotteryIdToLottery[lotteryId];
        require(
            lottery.state == lotteryState.ACTIVE,
            ""
        );
        return _amountToRepay(lottery);
    }

    function getLotteryExpirationDate(
        uint256 lotteryId
    ) public view virtual returns (uint256) 
    {
        return _lotteryIdToLottery[lotteryId].expirationDate;
    }

    function getLotteryOwner(
        uint256 lotteryId
    ) public view virtual returns (address) 
    {
        return _lotteryIdToLottery[lotteryId].owner;
    }

    function getLotteryPrizeContract(
        uint256 lotteryId
    ) public view virtual returns (address) 
    {
        return address(_lotteryIdToLottery[lotteryId].prizeContract);
    }

    function getLotteryPrizeTokenId(
        uint256 lotteryId
    ) public view virtual returns (uint256) 
    {
        return _lotteryIdToLottery[lotteryId].prizeTokenId;
    }

    function getLotteryState(
        uint256 lotteryId
    ) public view virtual returns (lotteryState) 
    {
        return _lotteryIdToLottery[lotteryId].state;
    }

    function getWinner(
        uint256 lotteryId
    ) public view virtual returns (address) 
    {
        return _lotteryIdToLottery[lotteryId].winner;
    }

    function getLotteryWonkaBarsSold(
        uint256 lotteryId
    ) public view virtual returns (uint256) 
    {
        return _lotteryIdToLottery[lotteryId].wonkaBarsSold;
    }

    function getLotteryWonkaBarsMaxSupply(
        uint256 lotteryId
    ) public view virtual returns (uint256) 
    {
        return _lotteryIdToLottery[lotteryId].wonkaBarsMaxSupply;
    }

    function getLotteryWonkaBarPrice(
        uint256 lotteryId
    ) public view virtual returns (uint256) 
    {
        return _lotteryIdToLottery[lotteryId].wonkaBarPrice;
    }

    /**
     * Creates a new lottery.
     *
     * @param expirationDate expiration date of the lottery.
     * @param prizeContract address of the prize NFT contract.
     * @param prizeTokenId ID of the prize NFT token.
     * @param wonkaBarPrice price of each WonkaBar, in ChocoChips.
     * @param wonkaBarsMaxSupply maximum supply of WonkaBars for the lottery.
     * @return lotteryId of the newly created lottery.
     */
    function createLottery(
        uint256 expirationDate,
        IERC721 prizeContract,
        uint256 prizeTokenId,
        uint256 wonkaBarPrice,
        uint256 wonkaBarsMaxSupply
    ) public virtual returns (uint256) 
    {
        require(
            prizeContract.ownerOf(prizeTokenId) == _msgSender(), 
            ""
        );
        require(
            block.timestamp < expirationDate, 
            ""
        );
        require(
            (wonkaBarsMaxSupply / 100) * _upperLimitPercentage >= 1, 
            ""
        );

        prizeContract.safeTransferFrom(
            _msgSender(),
            address(this),
            prizeTokenId
        );

        uint256 lotteryId = _totalLotteriesCreated;
        /// Incrementing the total number of lotteries created.
        _totalLotteriesCreated += 1;

        /// Creating the lottery.
        Lottery memory lottery = Lottery(
            expirationDate,
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

        _storeNewLottery(lottery);

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
    ) payable public virtual 
    {
        Lottery memory lottery = _lotteryIdToLottery[lotteryId];

        uint256 totalSpending = amount * lottery.wonkaBarPrice;

        /// The lottery must be active.
        require(
            lottery.state == lotteryState.ACTIVE, 
            ""
        );
        /// The total supply of WonkaBars must not exceed the maximum supply allowed.
        require(
            lottery.wonkaBarsSold + amount <= lottery.wonkaBarsMaxSupply,
            ""
        );
        ///
        require(
            (_contractWonkaBar.balanceOf(_msgSender(), lottery.id) + amount) / lottery.wonkaBarsMaxSupply 
            <=
            _upperLimitPercentage / 100,
            ""
        );
        ///
        require(
            msg.value >= totalSpending, 
            ""
        );

        uint256 valueToDAO = (totalSpending / 100) * _royaltyDAOPercentage;
        Address.sendValue(payable(_addressMeltyFiDAO()), valueToDAO);

        uint256 valueToLotteryOwner = totalSpending - valueToDAO;
        Address.sendValue(payable(lottery.owner), valueToLotteryOwner);

        _contractWonkaBar.mint(_msgSender(), lottery.id, amount, "");

        Lottery storage sLottery = _lotteryIdToLottery[lottery.id];
        sLottery.wonkaBarsSold += amount;

        _lotteryStateToClassInfoToLotteryAddressTolotteryIds[
            lottery.state][
                classInfo.WONKABARHOLDER][
                    _msgSender()].add(lottery.id);

        _lotteryStateToClassInfoToAddresses[
            lottery.state][
                classInfo.WONKABARHOLDER].add(_msgSender());

    }

    function repayLoan(uint256 lotteryId) public payable virtual {
        
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
            lottery.state == lotteryState.ACTIVE, 
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

        Lottery storage sLottery = _lotteryIdToLottery[lottery.id];
        sLottery.state == lotteryState.CANCELLED;

        _checkIfToTrash(lottery);

    }

    function meltWonkaBars(uint256 lotteryId, uint256 amount) public virtual {
        
        Lottery memory lottery = _lotteryIdToLottery[lotteryId];
        uint256 totalRefunding = _amountToRefund(lottery, _msgSender());

        require(
            _contractWonkaBar.balanceOf(_msgSender(), lottery.id) >= amount,
            ""
        );

        require(
            lottery.state == lotteryState.CANCELLED 
            ||
            lottery.state == lotteryState.CONCLUDED,
            ""
        );

        _contractWonkaBar.burn(_msgSender(), lottery.id, amount);

        _contractChocoChip.mint(
            _msgSender(),
            totalRefunding * _amountChocoChipPerEther
        );

        if (lottery.state == lotteryState.CANCELLED) {
            Address.sendValue(payable(_msgSender()), totalRefunding);
        }

        if (_contractWonkaBar.balanceOf(_msgSender(), lottery.id) == 0) {

            _lotteryStateToClassInfoToLotteryAddressTolotteryIds[
            lottery.state][
                classInfo.WONKABARHOLDER][
                    _msgSender()].remove(lottery.id);

            _lotteryStateToClassInfoToAddresses[
                lottery.state][
                    classInfo.WONKABARHOLDER].remove(_msgSender());
        }

        _checkIfToTrash(lottery);

    }

    function drawWinner(
        uint256 lotteryId, 
        address winner
    ) public virtual 
    {

    }
}

/**
 * @dev
 * il lender riceve 1 choc pari al numero di finney spesi in ticket
 * il bowworare riceve 1 choc pari al numero di finney spesi in interessi
 *
 */
