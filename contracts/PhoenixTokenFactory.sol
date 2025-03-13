// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9 <0.9.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract PhoenixTokenFactory is Ownable {
    using SafeERC20 for ERC20;

    struct TokenInfo {
        address owner;
        address tokenAddress;
        string name;
        string symbol;
        uint256 totalSupply;
        uint8 decimals;
    }

    address public immutable treasury;
    uint256 public constant MINT_FEE_PERCENT = 5; // 0.5%
    uint256 public constant FEE_DENOMINATOR = 1000; // Denominator for fee calculation
    uint256 public totalTokenCreated; // returns total tokens created so far

    TokenInfo[] public allTokens;
    mapping(address => TokenInfo[]) public userTokens;

    event TokenCreated(
        address indexed owner,
        address indexed tokenAddress,
        string name,
        string symbol,
        uint256 totalSupply
    );

    constructor(address _treasury) Ownable(msg.sender) {
        require(_treasury != address(0), "Invalid treasury address");
        treasury = _treasury;
    }

    function createToken(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint8 _decimals
    ) external {
        require(_totalSupply > 0, "Supply must be greater than 0");

        PhoenixERC20 newToken = new PhoenixERC20(
            _name,
            _symbol,
            _totalSupply,
            _decimals,
            msg.sender,
            treasury,
            MINT_FEE_PERCENT,
            FEE_DENOMINATOR
        );

        TokenInfo memory info = TokenInfo({
            owner: msg.sender,
            tokenAddress: address(newToken),
            name: _name,
            symbol: _symbol,
            totalSupply: _totalSupply,
            decimals: _decimals
        });

        allTokens.push(info);
        userTokens[msg.sender].push(info);
        totalTokenCreated++;
        emit TokenCreated(
            msg.sender,
            address(newToken),
            _name,
            _symbol,
            _totalSupply
        );
    }

    function getUserTokens(address user)
        external
        view
        returns (TokenInfo[] memory)
    {
        return userTokens[user];
    }
}

contract PhoenixERC20 is ERC20, Ownable {
    uint8 private _decimals;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint8 decimals_,
        address _owner,
        address _treasury,
        uint256 _fee,
        uint256 _feeDenominator
    ) ERC20(_name, _symbol) Ownable(_owner) {
        uint256 fee = (_totalSupply * _fee) / _feeDenominator;
        uint256 ownerAmount = _totalSupply - fee;
        _decimals = decimals_;
        _mint(_owner, ownerAmount);
        _mint(_treasury, fee);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
