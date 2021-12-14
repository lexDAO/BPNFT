// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts@4.4.0/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts@4.4.0/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts@4.4.0/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts@4.4.0/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts@4.4.0/security/Pausable.sol";
import "@openzeppelin/contracts@4.4.0/access/Ownable.sol";
import "@openzeppelin/contracts@4.4.0/utils/Counters.sol";

/// @notice BPNFT Minter with Governance
contract BowlProducers is ERC721, ERC721Enumerable, ERC721URIStorage, ERC721Burnable, Pausable, Ownable {
    using Counters for Counters.Counter;

    /*///////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    Counters.Counter private _tokenIdCounter;

    /// @dev initial mint URI that can be amended
    string public placeholderURI;

    /// @dev counter for mint phases
    uint256 public mintPhase;

    /// @dev limit for minting - also checked by cap
    uint256 public mintPhaseLimit;

    /// @dev ETH price to mint
    uint256 public mintPrice;

    /// @dev total supply cap
    uint256 public immutable mintCap;

    /// @dev mint restriction status - if true, nobody can mint
    bool public mintOpen;

    /// @dev whitelist status - if true, only approved can mint
    bool public whitelistOn;

    /// @dev whitelisted accounts
    mapping(address => bool) public whitelist;

    /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory placeholderURI_, 
        uint256 mintPhaseLimit_,
        uint256 mintPrice_, 
        uint256 mintCap_,
        bool mintOpen_,
        bool whitelistOn_
    ) ERC721("Bowl Producers", "BPNFT") {
        placeholderURI = placeholderURI_;

        mintPhaseLimit = mintPhaseLimit_;

        mintPrice = mintPrice_;

        mintCap = mintCap_;

        mintOpen = mintOpen_;

        whitelistOn = whitelistOn_;

        mintPhase++;
    }

    /*///////////////////////////////////////////////////////////////
                            MINT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev claim tokenId mints with placeholder URI in batch 'phase'
    function safeMint() external payable {
        // check mint is open
        require(mintOpen, 'CLOSED');
        // check whitelist if toggled on
        if (whitelistOn) require(whitelist[msg.sender], 'NOT_WHITELISTED');
        // check if price attached
        require(msg.value == mintPrice, 'BAD_PRICE');
        // increment Id for mint (we want to match supply for ease)
        _tokenIdCounter.increment();
        // set tokenId
        uint256 tokenId = _tokenIdCounter.current();
        // check new Id doesn't pass mint limit for phase
        require(tokenId <= mintPhaseLimit, 'PHASE_LIMIT');
        // mint Id to caller
        _safeMint(msg.sender, tokenId);
        // set Id placeholder URI
        _setTokenURI(tokenId, placeholderURI);
        // forward ETH to contract owner
        _safeTransferETH(owner(), msg.value);
    }

    /*///////////////////////////////////////////////////////////////
                            GOV LOGIC
    //////////////////////////////////////////////////////////////*/

    /// **** MINT MGMT

    /// @dev set next phase for minting (limit + price)
    function setMintPhase(uint256 mintPhaseLimit_, uint256 mintPrice_) external onlyOwner {
        // ensure id limit doesn't exceed cap
        require(mintPhaseLimit_ <= mintCap, 'CAPPED');
        // ensure id limit is greater than current supply (increasing phase)
        require(mintPhaseLimit_ > totalSupply(), 'BAD_LIMIT');
        // set new minting limit under cap
        mintPhaseLimit = mintPhaseLimit_;
        // set new minting price
        mintPrice = mintPrice_;
        // increment phase for tracking
        mintPhase++;
    }

    /// @dev set just mint price
    function setMintPrice(uint256 mintPrice_) external onlyOwner {
        mintPrice = mintPrice_;
    }

    /// @dev extra safety valve to restrict minting
    function setMintStatus(bool mintOpen_) external onlyOwner {
        mintOpen = mintOpen_;
    }

    /// **** URI MGMT

    /// @dev update base 'placeholder' URI for mints
    function setPlaceholderURI(string calldata placeholderURI_) external onlyOwner {
        placeholderURI = placeholderURI_;
    }

    /// @dev update minted URIs
    function setURIs(uint256[] calldata tokenIds, string[] calldata uris) external onlyOwner {
        require(tokenIds.length == uris.length, 'NO_ARRAY_PARITY');

        // this is reasonably safe from overflow because incrementing `i` loop beyond
        // 'type(uint256).max' is exceedingly unlikely compared to optimization benefits
        unchecked {
            for (uint256 i; i < tokenIds.length; i++) {
                _setTokenURI(tokenIds[i], uris[i]);
            }
        }
    }

    /// **** WHITELIST MGMT

    /// @dev whitelist account
    function setWhitelist(address account, bool approved) external onlyOwner {
        whitelist[account] = approved;
    }

    /// @dev flip whitelisting status
    function toggleWhitelist() external onlyOwner {
        whitelistOn = !whitelistOn;
    }

    /// **** TRANSFER MGMT

    /// @dev freeze transfers
    function pause() external onlyOwner {
        _pause();
    }

    /// @dev unfreeze transfers
    function unpause() external onlyOwner {
        _unpause();
    }

    /*///////////////////////////////////////////////////////////////
                            UTILS
    //////////////////////////////////////////////////////////////*/

    /// @dev the following functions are overrides required by Solidity:

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        whenNotPaused
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    /// @dev ETH tranfer helper - optimized in assembly:

    function _safeTransferETH(address to, uint256 amount) internal {
        bool callStatus;

        assembly {
            // transfer the ETH and store if it succeeded or not
            callStatus := call(gas(), to, amount, 0, 0, 0, 0)
        }

        require(callStatus, 'ETH_TRANSFER_FAILED');
    }
}
