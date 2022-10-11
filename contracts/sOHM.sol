/**
 *Submitted for verification at Etherscan.io on 2021-06-12
*/

// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;
import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";
import "./libraries/Counters.sol";
import "./interfaces/IERC20.sol";
import "./types/ERC20Permit.sol";
import "./Ownable.sol";



/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */


contract sOlympus is ERC20Permit, Ownable {

    using SafeMath for uint256;

    // Staking Contract만 호출 할 수 있는 접근제한자 Modifier
    modifier onlyStakingContract() {
        require( msg.sender == stakingContract );
        _;
    }
    
    // stakingContract 주소값 변수
    address public stakingContract;
    // initailzier 주소값 변수
    address public initializer;


    event LogSupply(uint256 indexed epoch, uint256 timestamp, uint256 totalSupply );
    event LogRebase( uint256 indexed epoch, uint256 rebase, uint256 index );
    event LogStakingContractUpdated( address stakingContract );

    // Rebase 구조체
    struct Rebase {
        uint epoch;
        uint rebase; // 18 decimals
        uint totalStakedBefore;
        uint totalStakedAfter;
        uint amountRebased;
        uint index;
        uint blockNumberOccured;
    }

    // Rebase 구조체 자료형의 배열을 rebases로 선언
    Rebase[] public rebases;

    uint public INDEX;
    // uint256 MAX값 = 2 ** 256 - 1 = 115792089237316195423570985008687907853269984665640564039457584007913129639935
    uint256 private constant MAX_UINT256 = ~uint256(0);
    // sOHM 초기 파편 발행량?? 5백만개
    uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 5000000 * 10**9;

    // TOTAL_GONS is a multiple of INITIAL_FRAGMENTS_SUPPLY so that _gonsPerFragment is an integer.
    // Use the highest value that fits in a uint256 for max granularity.

    // ToTAL_GONS = MAX_UINT256 - 4007913129639936
    uint256 public constant TOTAL_GONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);

    // MAX_SUPPLY = maximum integer < (sqrt(4*TOTAL_GONS + 1) - 1) / 2
    // 340282366920938463463374607431768211455 = (2 ** 128) - 1
    uint256 private constant MAX_SUPPLY = ~uint128(0);  // (2^128) - 1

    uint256 public _gonsPerFragment;
    mapping(address => uint256) public _gonBalances;

    mapping ( address => mapping ( address => uint256 ) ) private _allowedValue;

    /** 
        constructor()함수  
        토큰 이름, symbol, decimal, initalizer, 현재까지 총 발행량, 조각당gon값을 세팅
    */
    constructor() ERC20("Staked Olympus", "sOHM", 9) ERC20Permit() {
        initializer = msg.sender;
        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);
    }

    /**
    initalize() 함수
    stakingContract 주소 세팅, 이주소의 gon자산값 세팅하는 함수
    */

    function initialize( address stakingContract_ ) external returns ( bool ) {
        require( msg.sender == initializer,"Not owner" );
        require( stakingContract_ != address(0) );
        stakingContract = stakingContract_;
        _gonBalances[ stakingContract ] = TOTAL_GONS;

        emit Transfer( address(0x0), stakingContract, _totalSupply );
        emit LogStakingContractUpdated( stakingContract_ );
        
        initializer = address(0);
        return true;
    }

    function setIndex( uint _INDEX ) external onlyManager() returns ( bool ) {
        require( INDEX == 0 );
        INDEX = gonsForBalance( _INDEX );
        return true;
    }

    /**
        @notice increases sOHM supply to increase staking balances relative to profit_
        @param profit_ uint256
        @return uint256
     */

     /**
     rebase 함수 : profit_ epoch_값을 넣어서 실행 StakingContract 컨트랙트 주소만 호출 가능
     함수 내부에서 쓰일 rebaseAmount 변수 선언, circulatingSupply는 circulationSupply()함수의 호출값으로 설정
     경우 1 profit_ == 0일때 _totalSupply값을 return 하고 함수 종료
     경우 2 circulationgSupply 값이 0보다 클때 rebaseAmount값을 profit_ * _totalSupply / circulatingSupply_값으로 변경 -> 총발행량을 이전 총발행량 + rebaseAmount값으로 변경 ->
     변경된 총발행량이 최대 발행량보다 많아지면 총발행량을 최대발행량이랑 같도록 변경 -> 조각당_gon깂을 총GONS / 총발행량으로 변경 -> _storeRebase함수에 매개변수를 넣어 호출 -> 변경된 총 발행량 값을 리턴
     위 두 경우에 포함이 안되어있을때 rebaseAmount값을 profit_ 로 변경 -> 발행량을 이전 총발행량 + rebaseAmount값으로 변경 ->
     변경된 총발행량이 최대 발행량보다 많아지면 총발행량을 최대발행량이랑 같도록 변경 -> 조각당_gon깂을 총GONS / 총발행량으로 변경 -> _storeRebase함수에 매개변수를 넣어 호출 -> 변경된 총 발행량 값을 리턴
     */
    function rebase( uint256 profit_, uint epoch_ ) public onlyStakingContract() returns ( uint256 ) {
        // 총 리베이스 선언
        uint256 rebaseAmount;
        // 좌항의값 = _totalsupply - balanceOf(stakingContract) = 10000
        uint256 circulatingSupply_ = circulatingSupply();

        //이율이 0 일때는 _totalsupply return
        if ( profit_ == 0 ) {
            emit LogSupply( epoch_, block.timestamp, _totalSupply );
            emit LogRebase( epoch_, 0, index() );
            return _totalSupply;
        } else if ( circulatingSupply_ > 0 ){
            // cirSu > 0 일때 rebaseAmount를 20 * 5000000 / 
            rebaseAmount = profit_.mul( _totalSupply ).div( circulatingSupply_ );
        } else {
            rebaseAmount = profit_;
        }

        _totalSupply = _totalSupply.add( rebaseAmount );

        if ( _totalSupply > MAX_SUPPLY ) {
            _totalSupply = MAX_SUPPLY;
        }
        // profit 값이 증가할때 마다 gonsPerFragment 값은 감소 할 수 밖에 없음.
        _gonsPerFragment = TOTAL_GONS.div( _totalSupply );

        _storeRebase( circulatingSupply_, profit_, epoch_ );

        return _totalSupply;
    }

    /**
        @notice emits event with data about rebase
        @param previousCirculating_ uint
        @param profit_ uint
        @param epoch_ uint
        @return bool
     */
    function _storeRebase( uint previousCirculating_, uint profit_, uint epoch_ ) public returns ( bool ) {
        uint rebasePercent = profit_.mul( 1e18 ).div( previousCirculating_ );

        rebases.push( Rebase ( {
            epoch: epoch_,
            rebase: rebasePercent, // 18 decimals
            totalStakedBefore: previousCirculating_,
            totalStakedAfter: circulatingSupply(),
            amountRebased: profit_,
            index: index(),
            blockNumberOccured: block.number
        }));
        
        emit LogSupply( epoch_, block.timestamp, _totalSupply );
        emit LogRebase( epoch_, rebasePercent, index() );

        return true;
    }
    // 지정한 주소의 gon자산을 반환해주는 함수
    function balanceOf( address who ) public view override returns ( uint256 ) {
        return _gonBalances[ who ].div( _gonsPerFragment );
    }
    // 지정한 총값의
    function gonsForBalance( uint amount ) public view returns ( uint ) {
        return amount.mul( _gonsPerFragment );
    }

    function balanceForGons( uint gons ) public view returns ( uint ) {
        return gons.div( _gonsPerFragment );
    }

    // Staking contract holds excess sOHM
    function circulatingSupply() public view returns ( uint ) {
        return _totalSupply.sub( balanceOf( stakingContract ) -10000 );
    }


    function index() public view returns ( uint ) {
        return balanceForGons( INDEX );
    }

    function transfer( address to, uint256 value ) public override returns (bool) {
        uint256 gonValue = value.mul( _gonsPerFragment );
        _gonBalances[ msg.sender ] = _gonBalances[ msg.sender ].sub( gonValue );
        _gonBalances[ to ] = _gonBalances[ to ].add( gonValue );
        emit Transfer( msg.sender, to, value );
        return true;
    }

    function allowance( address owner_, address spender ) public view override returns ( uint256 ) {
        return _allowedValue[ owner_ ][ spender ];
    }

    function transferFrom( address from, address to, uint256 value ) public override returns ( bool ) {
       _allowedValue[ from ][ msg.sender ] = _allowedValue[ from ][ msg.sender ].sub( value );
       emit Approval( from, msg.sender,  _allowedValue[ from ][ msg.sender ] );

        uint256 gonValue = gonsForBalance( value );
        _gonBalances[ from ] = _gonBalances[from].sub( gonValue );
        _gonBalances[ to ] = _gonBalances[to].add( gonValue );
        emit Transfer( from, to, value );

        return true;
    }

    function approve( address spender, uint256 value ) public override returns (bool) {
         _allowedValue[ msg.sender ][ spender ] = value;
         emit Approval( msg.sender, spender, value );
         return true;
    }

    // What gets called in a permit
    function _approve( address owner, address spender, uint256 value ) internal override virtual {
        _allowedValue[owner][spender] = value;
        emit Approval( owner, spender, value );
    }

    function increaseAllowance( address spender, uint256 addedValue ) public override returns (bool) {
        _allowedValue[ msg.sender ][ spender ] = _allowedValue[ msg.sender ][ spender ].add( addedValue );
        emit Approval( msg.sender, spender, _allowedValue[ msg.sender ][ spender ] );
        return true;
    }

    function decreaseAllowance( address spender, uint256 subtractedValue ) public override returns (bool) {
        uint256 oldValue = _allowedValue[ msg.sender ][ spender ];
        if (subtractedValue >= oldValue) {
            _allowedValue[ msg.sender ][ spender ] = 0;
        } else {
            _allowedValue[ msg.sender ][ spender ] = oldValue.sub( subtractedValue );
        }
        emit Approval( msg.sender, spender, _allowedValue[ msg.sender ][ spender ] );
        return true;
    }
}