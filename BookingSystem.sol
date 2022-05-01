// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.13;

import "./Flight.sol";
import "./BookingContract.sol";

interface BookingSystem {

    function initiateBooking(string memory _flightNumber, Flight.SeatCategory _seatCategory) 
        external 
        payable
        returns(string memory);

    function getBookingData(address customer) 
        external view
        returns (BookingContract.BookingData memory);
    
    function confirmBooking(address customer) external;

    function cancelBooking() external;

    function confirmCancelBooking(address customer) external payable;

    function cancelFlight(string memory _flightNumber) external payable;

    function getFlightCancellationRefundValue(string memory _flightNumber) external view returns(uint);

    function updateFlightStatus(string memory _flightNumber, Flight.FlightState _state) external;

    function getFlightData(string memory _flightNumber) external view returns (Flight.FlightData memory);

}