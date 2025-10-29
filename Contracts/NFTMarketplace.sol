// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title NFT Marketplace
 * @dev A decentralized marketplace for buying and selling NFTs with royalty support
 */
contract NFTMarketplace is ReentrancyGuard, Ownable {
    
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        bool isActive;
    }
    
    // Mapping from listing ID to Listing
    mapping(uint256 => Listing) public listings;
    
    // Mapping from NFT contract to token ID to listing ID
    mapping(address => mapping(uint256 => uint256)) public nftToListing;
    
    // Royalty percentage (e.g., 250 = 2.5%)
    mapping(address => mapping(uint256 => uint256)) public royalties;
    mapping(address => mapping(uint256 => address)) public creators;
    
    uint256 public listingCounter;
    uint256 public platformFee = 250; // 2.5% platform fee
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    event NFTListed(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 price
    );
    
    event NFTSold(
        uint256 indexed listingId,
        address indexed buyer,
        address indexed seller,
        uint256 price
    );
    
    event ListingCancelled(uint256 indexed listingId);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev List an NFT for sale
     * @param _nftContract Address of the NFT contract
     * @param _tokenId Token ID of the NFT
     * @param _price Sale price in wei
     */
    function listNFT(
        address _nftContract,
        uint256 _tokenId,
        uint256 _price
    ) external nonReentrant {
        require(_price > 0, "Price must be greater than zero");
        
        IERC721 nft = IERC721(_nftContract);
        require(nft.ownerOf(_tokenId) == msg.sender, "Not the NFT owner");
        require(
            nft.getApproved(_tokenId) == address(this) || 
            nft.isApprovedForAll(msg.sender, address(this)),
            "Marketplace not approved"
        );
        
        listingCounter++;
        uint256 listingId = listingCounter;
        
        listings[listingId] = Listing({
            seller: msg.sender,
            nftContract: _nftContract,
            tokenId: _tokenId,
            price: _price,
            isActive: true
        });
        
        nftToListing[_nftContract][_tokenId] = listingId;
        
        // Set creator if not already set (for royalties)
        if (creators[_nftContract][_tokenId] == address(0)) {
            creators[_nftContract][_tokenId] = msg.sender;
            royalties[_nftContract][_tokenId] = 500; // 5% default royalty
        }
        
        emit NFTListed(listingId, msg.sender, _nftContract, _tokenId, _price);
    }
    
    /**
     * @dev Buy an NFT from the marketplace
     * @param _listingId ID of the listing to purchase
     */
    function buyNFT(uint256 _listingId) external payable nonReentrant {
        Listing storage listing = listings[_listingId];
        
        require(listing.isActive, "Listing is not active");
        require(msg.value == listing.price, "Incorrect payment amount");
        require(msg.sender != listing.seller, "Cannot buy your own NFT");
        
        listing.isActive = false;
        
        // Calculate fees
        uint256 platformFeeAmount = (listing.price * platformFee) / FEE_DENOMINATOR;
        uint256 royaltyAmount = (listing.price * royalties[listing.nftContract][listing.tokenId]) / FEE_DENOMINATOR;
        uint256 sellerAmount = listing.price - platformFeeAmount - royaltyAmount;
        
        // Transfer NFT to buyer
        IERC721(listing.nftContract).safeTransferFrom(
            listing.seller,
            msg.sender,
            listing.tokenId
        );
        
        // Transfer payments
        payable(listing.seller).transfer(sellerAmount);
        payable(creators[listing.nftContract][listing.tokenId]).transfer(royaltyAmount);
        payable(owner()).transfer(platformFeeAmount);
        
        emit NFTSold(_listingId, msg.sender, listing.seller, listing.price);
    }
    
    /**
     * @dev Cancel an active listing
     * @param _listingId ID of the listing to cancel
     */
    function cancelListing(uint256 _listingId) external nonReentrant {
        Listing storage listing = listings[_listingId];
        
        require(listing.isActive, "Listing is not active");
        require(listing.seller == msg.sender, "Not the seller");
        
        listing.isActive = false;
        
        emit ListingCancelled(_listingId);
    }
    
    /**
     * @dev Update platform fee (only owner)
     * @param _newFee New platform fee in basis points (e.g., 250 = 2.5%)
     */
    function updatePlatformFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 1000, "Fee too high"); // Max 10%
        platformFee = _newFee;
    }
    
    /**
     * @dev Get listing details
     * @param _listingId ID of the listing
     */
    function getListing(uint256 _listingId) external view returns (
        address seller,
        address nftContract,
        uint256 tokenId,
        uint256 price,
        bool isActive
    ) {
        Listing memory listing = listings[_listingId];
        return (
            listing.seller,
            listing.nftContract,
            listing.tokenId,
            listing.price,
            listing.isActive
        );
    }
}
