// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library EnumerableSetUint {
    struct UintSet {
        uint256[] _values;
        mapping(uint256 => uint256) _indexes;
    }

    function add(UintSet storage set, uint256 value) internal returns (bool) {
        if (!contains(set, value)) {
            set._values.push(value);
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    function remove(
        UintSet storage set,
        uint256 value
    ) internal returns (bool) {
        uint256 valueIndex = set._indexes[value];
        if (valueIndex != 0) {
            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;
            uint256 lastvalue = set._values[lastIndex];
            set._values[toDeleteIndex] = lastvalue;
            set._indexes[lastvalue] = toDeleteIndex + 1;
            set._values.pop();
            delete set._indexes[value];
            return true;
        } else {
            return false;
        }
    }

    function contains(
        UintSet storage set,
        uint256 value
    ) internal view returns (bool) {
        return set._indexes[value] != 0;
    }

    function length(UintSet storage set) internal view returns (uint256) {
        return set._values.length;
    }

    function at(
        UintSet storage set,
        uint256 index
    ) internal view returns (uint256) {
        require(
            set._values.length > index,
            "EnumerableSet: index out of bounds"
        );
        return set._values[index];
    }

    function getAll(
        UintSet storage set
    ) internal view returns (uint256[] memory) {
        return set._values;
    }

    function get(
        UintSet storage set,
        uint256 _page,
        uint256 _limit
    ) internal view returns (uint256[] memory) {
        require(_page > 0 && _limit > 0);
        uint256 tempLength = _limit;
        uint256 cursor = (_page - 1) * _limit;
        uint256 _uintLength = length(set);
        if (cursor >= _uintLength) {
            return new uint256[](0);
        }
        if (tempLength > _uintLength - cursor) {
            tempLength = _uintLength - cursor;
        }
        uint256[] memory uintList = new uint256[](tempLength);
        for (uint256 i = 0; i < tempLength; i++) {
            uintList[i] = at(set, cursor + i);
        }
        return uintList;
    }
}
