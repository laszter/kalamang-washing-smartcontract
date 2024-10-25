// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IAdminProjectRouter.sol";

abstract contract Authorization {
    IAdminProjectRouter public adminRouter;
    string public project;
    address public transferRouter;

    event SetAdmin(
        address indexed oldAdmin,
        address indexed newAdmin,
        address indexed caller
    );

    constructor(string memory project_) {
        project = project_;
    }

    modifier onlySuperAdmin() {
        require(
            adminRouter.isSuperAdmin(msg.sender, project),
            "Restricted only super admin"
        );
        _;
    }

    modifier onlyAdmin() {
        require(
            adminRouter.isAdmin(msg.sender, project),
            "Restricted only admin"
        );
        _;
    }

    modifier onlySuperAdminOrAdmin() {
        require(
            adminRouter.isSuperAdmin(msg.sender, project) ||
                adminRouter.isAdmin(msg.sender, project),
            "Restricted only super admin or admin"
        );
        _;
    }

    modifier onlySuperAdminOrTransferRouter() {
        require(
            adminRouter.isSuperAdmin(msg.sender, project) ||
                msg.sender == transferRouter,
            "Restricted only super admin ot transfer router"
        );
        _;
    }

    function setAdmin(address _adminRouter) external onlySuperAdmin {
        emit SetAdmin(address(adminRouter), _adminRouter, msg.sender);
        adminRouter = IAdminProjectRouter(_adminRouter);
    }

    function setTransferRouter(
        address _transferRouter
    ) external onlySuperAdmin {
        transferRouter = _transferRouter;
    }

    function setProject(string memory _project) external onlySuperAdmin {
        project = _project;
    }
}
