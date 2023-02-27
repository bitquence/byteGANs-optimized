// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "inflate-sol/InflateLib.sol";
import "sstore2/SSTORE2.sol";
import "ERC721A/ERC721A.sol";

contract byteGANs is ERC721A {
    using Metadata for address;

    uint256 constant MAXIMUM_SUPPLY = 1111;

    address immutable METADATA_POINTER;
    address[] contentPointers; // Non-value types cannot be immutable in Solidity yet

    constructor(address metadataPointer, address[] memory _contentPointers)
        ERC721A("byteGANs", "BYTE")
    {
        METADATA_POINTER = metadataPointer;
        contentPointers = _contentPointers;

        ERC721A._mint(msg.sender, MAXIMUM_SUPPLY);
    }

    /**
     * @dev See {ERC721A-_startTokenId}.
     */
    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    /**
     * @dev See {ERC721A-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(ERC721A._exists(tokenId), "byteGANs: invalid token ID");

        return METADATA_POINTER.tokenURI(tokenId, _startTokenId(), contentPointers);
    }
}

library Metadata {
    using SSTORE2 for address;
    using InflateLib for bytes;

    uint256 constant METADATA_CHUNK_SIZE = 8;

    uint256 constant TYPE_INDEX_OFFSET = 5;
    uint256 constant TYPE_SPECIFIC_ID_OFFSET = 9;
    uint256 constant CONTENT_POINTER_INDEX_OFFSET = 20;
    uint256 constant IMAGE_START_OFFSET = 25;
    uint256 constant COMPRESSED_SIZE_OFFSET = 40;
    uint256 constant ORIGINAL_SIZE_OFFSET = 50;

    uint256 constant SUBTYPE_INDEX_MASK = (1 << 5) - 1;
    uint256 constant TYPE_INDEX_MASK = (1 << 4) - 1;
    uint256 constant TYPE_SPECIFIC_ID_MASK = (1 << 11) - 1;
    uint256 constant CONTENT_POINTER_INDEX_MASK = (1 << 5) - 1;
    uint256 constant IMAGE_START_MASK = (1 << 15) - 1;
    uint256 constant COMPRESSED_SIZE_MASK = (1 << 10) - 1;
    uint256 constant ORIGINAL_SIZE_MASK = (1 << 11) - 1;

    struct TokenData {
        // Index of the token subtype's name (see `_subtypeName`)
        uint256 subtypeIndex;
        // Index of the token type's name (see `_typeName`)
        uint256 typeIndex;
        // Token identifier specific to its type/subtype pair, used to determine the token title
        uint256 typeSpecificId;
        // Index of the content pointer where the image is stored
        uint256 contentPointerIndex;
        // Starting offset of the compressed data in our content blob
        uint256 imageStart;
        // Size of our data when in compressed form
        uint256 compressedSize;
        // Original size of the compressed data, used for decompression
        uint256 originalSize;
    }

    // Takes in a bit-packed structure and returns a tagged, memory-allocated copy.
    //
    // `bits` should have the following layout (from least-significant to
    // most-significant bits, left and right inclusive range):
    //  - [0..4]    Subtype index
    //  - [5..8]    Type index
    //  - [9..19]   Type specific ID
    //  - [20..24]  Content pointer index
    //  - [25..39]  Image starting offset
    //  - [40..49]  Image compressed size
    //  - [50..59]  Image decompressed size
    //  - [60..63]  Unused excess bits
    function tokenDataFromBits(uint64 bits)
        internal
        pure
        returns (TokenData memory data)
    {
        return TokenData({
            subtypeIndex: bits & SUBTYPE_INDEX_MASK,
            typeIndex: (bits >> TYPE_INDEX_OFFSET) & TYPE_INDEX_MASK,
            contentPointerIndex: (bits >> CONTENT_POINTER_INDEX_OFFSET) & CONTENT_POINTER_INDEX_MASK,
            originalSize: (bits >> ORIGINAL_SIZE_OFFSET) & ORIGINAL_SIZE_MASK,
            imageStart: (bits >> IMAGE_START_OFFSET) & IMAGE_START_MASK,
            compressedSize: (bits >> COMPRESSED_SIZE_OFFSET) & COMPRESSED_SIZE_MASK,
            typeSpecificId: (bits >> TYPE_SPECIFIC_ID_OFFSET) & TYPE_SPECIFIC_ID_MASK
        });
    }

    function tokenURI(
        address metadataPointer,
        uint256 tokenId,
        uint256 startTokenId,
        address[] memory contentPointers
    ) internal view returns (string memory) {
        uint256 dataOffset = (tokenId - startTokenId) * METADATA_CHUNK_SIZE;

        // Reads the bit-packed data from our metadata contract.
        //
        // NOTE: `SSTORE2.read` already accounts for the `STOP` instruction that
        // prefixes our data by incrementing our start and ending position by 1
        uint64 tokenDataBits = uint64(
            bytes8(
                metadataPointer.read(
                    dataOffset,
                    dataOffset + METADATA_CHUNK_SIZE
                )
            )
        );

        // In the event that we somehow read a bunch of null data.
        //
        // The invariant that should be upheld in this instance is that metadata
        // must exist for any token that has been minted.
        assert(tokenDataBits != 0);

        // I decided to expand the packed data into a memory-allocated struct to
        // avoid the "stack too deep" compile error. We are also (most likely)
        // in a read only context by this point so gas usage becomes somewhat
        // irrelevant.
        TokenData memory token = tokenDataFromBits(tokenDataBits);

        bytes memory compressedGifFile = contentPointers[token.contentPointerIndex]
            .read(token.imageStart, token.imageStart + token.compressedSize);

        (InflateLib.ErrorCode err, bytes memory gifFile) = InflateLib.puff(
            compressedGifFile,
            token.originalSize
        );

        // This should be unreachable as per my unit test that compares every
        // output to what already exists on-chain.
        assert(err == InflateLib.ErrorCode.ERR_NONE);

        return _buildURI(token, gifFile);
    }

    function _buildURI(TokenData memory token, bytes memory gifFile) private pure returns (string memory) {
        string memory subtypeName = _subtypeName(token.subtypeIndex);
        string memory typeName = _typeName(token.typeIndex);

        string memory tokenName = string(
            abi.encodePacked(subtypeName, " ", typeName, " #", Strings.toString(token.typeSpecificId))
        );

        string memory traitsJson = string(
            abi.encodePacked(
                '['
                    '{'
                        '"trait_type":"subtype",'
                        '"value":"', subtypeName, '"'
                    '},'
                    '{'
                        '"trait_type":"type",'
                        '"value":"', typeName, '"'
                    '}'
                ']'
            )
        );

        // Display the GIF file in a specialized SVG page, to upscale it to
        // 500x500 all while retaining its pixelated quality
        bytes memory svgFile = bytes(
            abi.encodePacked(
                '<svg width="500" height="500" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"> '
                    '<image width="500" height="500" image-rendering="pixelated" xlink:href="data:image/gif;base64,', Base64.encode(gifFile), '"/> '
                '</svg>'
            )
        );

        bytes memory metadataJson = abi.encodePacked(
            '{'
                '"name":"', tokenName, '", '
                '"description":"bitGANs on-chained", '
                '"attributes":', traitsJson, ', '
                '"image": "data:image/svg+xml;base64,', Base64.encode(svgFile), '"'
            '}'
        );

        return string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(metadataJson)
                )
            );
    }

    function _typeName(uint256 index) private pure returns (string memory) {
        string[9] memory typeNames = [
            "cyberGAN",
            "octoGAN",
            "skullGAN",
            "ghostGAN",
            "g1itchGAN",
            "primeGAN",
            "apeGAN",
            "kingGAN",
            "queenGAN"
        ];

        return typeNames[index];
    }

    function _subtypeName(uint256 index) private pure returns (string memory) {
        string[24] memory subtypeNames = [
            "aqua",
            "bloody",
            "burning",
            "cerulean",
            "crypto",
            "cyanic",
            "decohering",
            "electric",
            "emerald",
            "ethereal",
            "frozen",
            "g1itch",
            "glowing",
            "inverted",
            "lime",
            "midnight",
            "primordial",
            "quantum",
            "radiating",
            "rosy",
            "spectral",
            "ultra",
            "viridian",
            "vivid"
        ];

        return subtypeNames[index];
    }
}
