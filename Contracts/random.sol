// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.24;

contract RandomRateExperiment {
    function randomNormal(
        uint256 total,
        uint256 amount
    ) public view returns (uint256[] memory) {
        uint256[] memory randoms = new uint256[](total);

        uint256 remain = amount;

        for (uint256 i = 0; i < total; i++) {
            if (i == total - 1) {
                randoms[i] = remain;
            } else {
                uint256 random = ((remain / (total - i)) *
                    (uint256(
                        keccak256(
                            abi.encodePacked(block.timestamp, msg.sender, i)
                        )
                    ) % 100)) / 100;

                if (random > remain) {
                    random = remain;
                }

                randoms[i] = random;
                remain -= random;
            }
        }

        return randoms;
    }

    function randomNormal2(
        uint256 total,
        uint256 amount
    ) public view returns (uint256[] memory) {
        uint256[] memory randoms = new uint256[](total);

        uint256 remain = amount;

        for (uint256 i = 0; i < total; i++) {
            if (i == total - 1) {
                randoms[i] = remain;
            } else {
                uint256 random = (remain *
                    (uint256(
                        keccak256(
                            abi.encodePacked(
                                block.timestamp,
                                msg.sender,
                                block.number
                            )
                        )
                    ) % 10000)) / 10000;

                if (random > remain) {
                    random = remain;
                }

                randoms[i] = random;
                remain -= random;
            }
        }

        return randoms;
    }

    function randomCeption(
        uint256 total,
        uint256 amount
    ) public view returns (uint256[] memory) {
        uint256[] memory randoms = new uint256[](total);

        uint256 remain = amount;

        for (uint256 i = 0; i < total; i++) {
            if (i == total - 1) {
                randoms[i] = remain;
            } else {
                uint256[] memory randomSets = new uint256[](10);

                for (uint256 j = 0; j < 10; j++) {
                    randomSets[j] =
                        ((remain / (total - i)) *
                            (uint256(
                                keccak256(
                                    abi.encodePacked(
                                        block.timestamp,
                                        msg.sender,
                                        i,
                                        j
                                    )
                                )
                            ) % 100)) /
                        100;
                }

                uint256 random = randomSets[
                    (uint256(
                        keccak256(
                            abi.encodePacked(
                                block.timestamp,
                                msg.sender,
                                i,
                                block.number
                            )
                        )
                    ) % 10)
                ];

                if (random > remain) {
                    random = remain;
                }

                randoms[i] = random;
                remain -= random;
            }
        }

        return randoms;
    }

    function randomRateControl(
        uint256 total,
        uint256 amount
    ) public view returns (uint256[] memory) {
        uint256[] memory randoms = new uint256[](total);

        uint256 remain = amount;

        for (uint256 i = 0; i < total; i++) {
            if (i == total - 1) {
                randoms[i] = remain;
            } else {
                uint256 randomPercentage = (uint256(
                    keccak256(
                        abi.encodePacked(
                            block.timestamp,
                            msg.sender,
                            block.number
                        )
                    )
                ) % 100) + 1;

                uint256 random = (remain * (100 - randomPercentage) ** 2) /
                    10000;

                if (random > remain) {
                    random = remain;
                }

                randoms[i] = random;
                remain -= random;
            }
        }

        return randoms;
    }

    function randomRateControl2(
        uint256 total,
        uint256 amount
    ) public view returns (uint256[] memory) {
        uint256[] memory randoms = new uint256[](total);

        uint256 remain = amount;
        uint256 baseAmount = (remain / total);

        for (uint256 i = 0; i < total; i++) {
            if (i == total - 1) {
                randoms[i] = remain;
            } else {
                uint256 random = baseAmount;
                uint256 randomError = (baseAmount *
                    ((uint256(
                        keccak256(
                            abi.encodePacked(block.timestamp, msg.sender, i)
                        )
                    ) % 100) / 100));

                if (
                    ((uint256(
                        keccak256(
                            abi.encodePacked(block.timestamp, msg.sender, i)
                        )
                    ) % 100) / 100) > 50
                ) {
                    random += randomError;
                } else {
                    random -= randomError;
                }

                if (random > remain) {
                    random = remain;
                }

                randoms[i] = random;
                remain -= random;
            }
        }

        return randoms;
    }
}
