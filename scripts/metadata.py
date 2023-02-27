import json
import zlib
import base64

data = json.loads(open("token_data.json").read())

type_names = [
    "cyberGAN",
    "octoGAN",
    "skullGAN",
    "ghostGAN",
    "g1itchGAN",
    "primeGAN",
    "apeGAN",
    "kingGAN",
    "queenGAN"
]

subtype_names = [
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
]

SMART_CONTRACT_SIZE_LIMIT = 24576
# We must account for the null byte we insert at the beginning of every contract
CONTRACT_DATA_OFFSET = 1

def init_code():
    # Courtesy of SSTORE2: https://github.com/0xsequence/sstore2/blob/0a28fe61b6e81de9a05b462a24b9f4ba8c70d5b7/contracts/utils/Bytecode.sol#L28
    return bytearray([0x60, 0x0B, 0x59, 0x81, 0x38, 0x03, 0x80, 0x92, 0x59, 0x39, 0xF3])

# Prefix our data with the `STOP` EVM opcode to prevent the execution of random instructions
metadata = bytearray([0x00])
content_contracts = [bytearray([0x00])]
content_contracts_index = 0

tokens = {}

for token_id, token in data.items():
    subtype_index = subtype_names.index(token["traits"][0]["value"])
    type_index = type_names.index(token["traits"][1]["value"])
    type_specific_id = int(token["name"].split("#")[1])

    raw_gif = base64.b64decode(token["gif"])

    original_size = len(raw_gif)

    # compress gif data (https://stackoverflow.com/a/1089787/19199696)
    compress = zlib.compressobj(9, zlib.DEFLATED, -zlib.MAX_WBITS, zlib.DEF_MEM_LEVEL, 0)
    deflated = compress.compress(raw_gif)
    deflated += compress.flush()

    # Allocate a new content contract once the current one is filled
    if len(content_contracts[content_contracts_index]) + len(deflated) + CONTRACT_DATA_OFFSET >= SMART_CONTRACT_SIZE_LIMIT:
        content_contracts_index += 1
        content_contracts.append(bytearray([0x00]))

    image_start = len(content_contracts[content_contracts_index]) - 1
    image_end = image_start + len(deflated)

    content_contracts[content_contracts_index] += deflated

    # This is the structure of our bit-packed word. Though its final size is 61
    # bits, the smallest unit the EXTCODECOPY opcode can copy is one byte. This
    # value takes up 8 bytes in our metadata contract.
    #
    # struct {
    #     uint5 subtype_index
    #     uint4 type_index
    #     uint11 type_specific_id
    #     uint5 content_pointer_index
    #     uint15 image_start
    #     uint10 compressed_size
    #     uint11 original_size
    # }
    packed = 0

    # I couldn't find a library to pack structs into bit units, so I am doing it manually

    # In reverse order:

    print(f"processing token #{token_id}")

    print("  > original_size: {0:b}".format(original_size))
    assert original_size.bit_length() <= 11
    packed |= original_size

    packed <<= 10

    print("  > compressed_size: {0:b}".format(len(deflated)))
    assert len(deflated).bit_length() <= 10
    packed |= len(deflated)

    packed <<= 15

    print("  > image_start: {0:b}".format(image_start))
    assert image_start.bit_length() <= 15
    packed |= image_start

    packed <<= 5

    print("  > content_contracts_index: {0:b}".format(content_contracts_index))
    assert content_contracts_index.bit_length() <= 5
    packed |= content_contracts_index

    packed <<= 11

    print("  > type_specific_id: {0:b}".format(type_specific_id))
    assert type_specific_id.bit_length() <= 11
    packed |= type_specific_id

    packed <<= 4

    print("  > type_index: {0:b}".format(type_index))
    assert type_index.bit_length() <= 4
    packed |= type_index
    
    packed <<= 5

    print("  > subtype_index: {0:b}".format(subtype_index))
    assert subtype_index.bit_length() <= 5
    packed |= subtype_index
    
    print(" > packed result (binary): {:0>64b}".format(packed))

    # Append the packed data, making sure to round it up to byte alignment (64 bits)
    metadata += bytes.fromhex("{:0>16x}".format(packed))

    tokens[token_id] = {
        "subtypeIndex": subtype_index,
        "typeIndex": type_index,
        "image": {
            "originalSize": original_size,
            "imageStart": image_start,
            "imageEnd": image_end,
            "imageLocationIndex": content_contracts_index,
        },
        "packedData": packed,
        "deflated": deflated.hex()
    }

assert len(metadata) <= SMART_CONTRACT_SIZE_LIMIT, "Metadata contract is too large"
assert all(map(lambda x: len(x) <= SMART_CONTRACT_SIZE_LIMIT, content_contracts)), "One of the content contracts are too large"

with open("metadata_result.json", "w") as f:
    f.write(
        json.dumps(
            {
                "initCodePrefix": init_code().hex(),
                "metadata": metadata.hex(),
                "data": list(map(bytearray.hex, content_contracts))
            }
        )
    )
