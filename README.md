# byteGANs-optimized

Gas-optimized variant of the smart contracts used for the [byteGANs NFT project](https://web.archive.org/web/20230226180138/https://bitgans.com/news/the-bytegans).

The bulk of this optimization comes from using contract code instead of contract storage as a means of storing media on-chain. This idea is explored more in-depth in [Agusx1211](https://github.com/Agusx1211)'s [SSTORE2 repository](https://github.com/0xsequence/sstore2).

To further optimize data size, the DEFLATE algorithm was used to compress the media - which is then decompressed during local read-only execution of the EVM - using [John Adler](https://github.com/adlerjohn)'s [Solidity port](https://github.com/adlerjohn/inflate-sol) of the [puff decompression algorithm](https://github.com/madler/zlib/tree/master/contrib/puff).

Using these two methods, it was possible to decrease the cost of uploading all of the media (excluding the token contract) from **861,895,252** to **111,605,818** gas used (nearly an 90% decrease).

The scripts used to generate the packed data for this project are stored at `./scripts/`. The only contract file `./src/byteGANs.sol` includes Solidity logic to fetch, decompress and encode our data into a readable metadata format

## Publication

More information can be found in my [Twitter thread](https://twitter.com/_bitquence).

## Credits

- [Van Arman](https://github.com/pindarvanarman) - artwork
- [Agustin Aguilar](https://github.com/Agusx1211) - original version of [SSTORE2](https://github.com/0xsequence/sstore2)
- [John Adler](https://github.com/adlerjohn) - [Solidity port](https://github.com/adlerjohn/inflate-sol) of the [puff decompression algorithm](https://github.com/madler/zlib/tree/master/contrib/puff)
