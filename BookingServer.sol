// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.13;

import "./Flight.sol";
import "./BookingContract.sol";

/**
 * @author GreatLearningGroup3
 * @title BookingServer
 * @dev This contract serves as an abtraction for two entities namely airlines and its passengers 
 * for performing various flight and its booking activities.
 *
 * For an Airline, flight activities comprises of updating flight status, view flight booking list
 * For a Passenger, flight activities comprises of booking flight ticket, cancel booking
 *
 * NOTE: This contract assumes that ETH to be used for tranfer of funds between entities. Also
 * exact value of the ticket in ethers is expected.
 */

contract BookingServer {

    Flight flight;

    enum State { BookingInitiated, BookingConfirmed, CancelInitiated, CancelConfirmed, Inactive }
    State state;
    address payable airlines;
    uint public penalty;
    uint public refundAmt;

    bool flightStateUpdated = false;
	
	event AmountTransferred(address from, address to, uint amountInEther, string transferReason);
    event cancelTransferred(address from, address to, uint amountInEther, uint256 currentTime, string transferReason);
    event BookingComplete(address customer, string flightId);
    event FlightCancelled(address airlines, string flightId);
    event LogEvent(address airline, address escrow, address customer);

    error InvalidState();

    mapping(uint => uint) private _penaltyMap; 
    mapping(address => BookingContract) private bookings;
    address[] customers;

    modifier inState(State state_) {
        if (state != state_)
            revert InvalidState();
        _;
    }

	modifier onlyCustomer(){
        require(msg.sender != airlines, "Only customer initiates the flight booking");
        _;
    }

    modifier onlyAirlines() {
        require(msg.sender == airlines, "Only airlines can do this action");
        _;
    }

    modifier onlyEscrow(address customer){
        require(msg.sender == address(bookings[customer]), "Only Escrow can do this action");
        _; 
    }

    modifier onlyValidAddress(address addr) {
        require(addr != address(0));
        _;
    }

    modifier onlyValidFlightNumber(string memory _flightNumber) {
        Flight.FlightData memory flightData = flight.getFlightData(_flightNumber);
        require(bytes(flightData.flightNumber).length > 0, "Invalid flight number");
        _;
    }

    modifier onlyValidFlightNumberAndState(string memory _flightNumber) {
        Flight.FlightData memory flightData = flight.getFlightData(_flightNumber);
         require(bytes(flightData.flightNumber).length > 0, "Invalid flight number");
        require(flightData.state != Flight.FlightState.CANCELLED, "Flight is Cancelled");
        _;
    }

    modifier onlyExactTicketAmount(string memory _flightNumber) {
        Flight.FlightData memory flightData = flight.getFlightData(_flightNumber);
        require(msg.value == flightData.ethAmount *10**18, "Exact booking ethers needed");
        _;
    }
	
	modifier onlySufficientFunds() {
		require(msg.sender.balance > msg.value, "Insufficient funds to book the ticket");
		_;
	}
	
	constructor() {
        flight = new Flight();
        flight.populateFlights();
        airlines = payable(msg.sender);
        emit LogEvent(airlines, msg.sender, msg.sender);
        _penaltyMap[2] = 80;
        _penaltyMap[12] = 60;
        _penaltyMap[24] = 40;
    }

    function initiateBooking(string memory _flightNumber, Flight.SeatCategory _seatCategory) 
        public 
        payable
        onlyCustomer
		onlyValidFlightNumberAndState(_flightNumber)
		onlySufficientFunds
        onlyExactTicketAmount(_flightNumber) returns(string memory){
		
        state = State.BookingInitiated;

        BookingContract booking = new BookingContract(msg.sender, airlines, msg.value);
        bookings[msg.sender] = booking;
        customers.push(msg.sender);
		emit AmountTransferred(msg.sender, address(booking), msg.value, "Booking amount");

        string memory bookingComment = booking.bookTicket(msg.sender, _seatCategory, _flightNumber);
		emit BookingComplete(msg.sender, _flightNumber);
        return bookingComment;
    }
	
	function getBookingData(address customer) 
        public view
        onlyAirlines returns (BookingContract.BookingData memory){
        return bookings[customer].getBookingData();
    }

     function confirmBooking(address customer)
        public 
        onlyAirlines
        inState(State.BookingInitiated){
        //check if customer cancelled the ticket or flight status is not cancelled before 24 hours
        require(flightStateUpdated, "Flight status not updated in last 24 hours");
		
        BookingContract.BookingData memory bookingData = bookings[customer].getBookingData();
        Flight.FlightData memory flightData = flight.getFlightData(bookingData.flightNumber);

        if(flightData.state  != Flight.FlightState.CANCELLED) {
            payable(airlines).transfer(bookings[customer].getValue());
            state = State.BookingConfirmed;
            emit AmountTransferred(msg.sender, bookingData.airlines, bookings[customer].getValue(), 
            "Escrow transferred the ticket amount to the airlines");
        }
    }

    function cancelBooking()
        public
        onlyCustomer 
        inState(State.BookingInitiated) {
        
         //Retrieve the booking based on either customer address or confirmationId
        BookingContract.BookingData memory bookingData = bookings[msg.sender].getBookingData();
        Flight.FlightData memory flightData = flight.getFlightData(bookingData.flightNumber);

        //Requires current time is 2 hours before the flight time
        require(block.timestamp < flightData.flightTime - 2 hours, "There is less than 2 hours for flight departure. Hence can't cancel the ticket");
        
        //Calculate Refund and Penalty
        if((block.timestamp < flightData.flightTime - 2 hours) && (block.timestamp > flightData.flightTime - 12 hours)){
            penalty = (_penaltyMap[2]*flightData.ethAmount)/100;
            refundAmt = flightData.ethAmount - penalty;
        } else if((block.timestamp < flightData.flightTime - 12 hours) && (block.timestamp > flightData.flightTime - 24 hours)){
            penalty = (_penaltyMap[12]*flightData.ethAmount)/100;
            refundAmt = flightData.ethAmount - penalty;
        } else if((block.timestamp < flightData.flightTime - 24 hours) && (block.timestamp > flightData.flightTime - 48 hours)){
            penalty = (_penaltyMap[24]*flightData.ethAmount)/100;
            refundAmt = flightData.ethAmount - penalty;
        } else {
            refundAmt = flightData.ethAmount;
        }

        emit cancelTransferred(msg.sender, bookingData.airlines, refundAmt, block.timestamp, "Cancel window");
        state = State.CancelInitiated;
        //Transfer funds to both the parties
        bookings[msg.sender].cancelBooking();
    }

    function confirmCancelBooking(address customer)
        public 
        payable
        onlyEscrow(customer)
        inState(State.CancelInitiated){
		
        BookingContract.BookingData memory bookingData = bookings[msg.sender].getBookingData();
        // Transfer refund from escrow to the customer and transfer peanlty to the airlines
        payable(bookingData.airlines).transfer(penalty*10**18);
        payable(customer).transfer(refundAmt*10**18);
        state = State.CancelConfirmed;
		emit AmountTransferred(msg.sender, bookingData.airlines, penalty, "Escrow transferred the penalty to the airlines and refunded to the customer");
    }

	function cancelFlight(string memory _flightNumber) 
        public
        payable
		onlyAirlines
        onlyValidFlightNumberAndState(_flightNumber) 
        onlyValidFlightNumber(_flightNumber) {
        
        flight.setFlightState(_flightNumber, Flight.FlightState.CANCELLED);
        emit FlightCancelled(msg.sender, _flightNumber);

        for(uint i = 0; i < customers.length; i++) {
            if (bookings[customers[i]].getBookingData().state != BookingContract.BookingState.CANCELLED) {
                payable(customers[i]).transfer(flight.getFlightData(_flightNumber).ethAmount*10**18);
                bookings[customers[i]].flightCancelled();
                emit AmountTransferred(msg.sender, customers[i], bookings[customers[i]].getValue(), "Flight Cancel Refund"); 
            }  
        }
    }

    function getFlightCancellationRefundValue(string memory _flightNumber) public view returns(uint) {
        uint boardingCustomerCount = 0;
        for(uint i = 0; i < customers.length; i++) {
            if (bookings[customers[i]].getBookingData().state != BookingContract.BookingState.CANCELLED) {
                boardingCustomerCount++;
            }
        }
        return boardingCustomerCount * flight.getFlightData(_flightNumber).ethAmount;
    }

    function updateFlightStatus(string memory _flightNumber, Flight.FlightState _state) 
		public 
		onlyAirlines 
		onlyValidFlightNumber(_flightNumber) {
            require (block.timestamp > flight.getFlightData(_flightNumber).flightTime - 24 hours, "Updates permitted 24 hrs before flight departure time");
            flightStateUpdated = true;
            flight.setFlightState(_flightNumber, _state);    
    }

	function getFlightData(string memory _flightNumber) 
        public view 
        onlyValidFlightNumber(_flightNumber) returns (Flight.FlightData memory) {
        return flight.getFlightData(_flightNumber);
    }
}