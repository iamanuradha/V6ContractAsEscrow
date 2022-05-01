Ticket Management System for an airline system

BookingServer deployed by Airlines
BookingContract between airline and customer serves as escrow
Flight contract holds static flight data and utility methods.

A. Booking Ticket Flow
1. Airline deploys the contract
2. Customer sets the flight price as message value in ethers, calls initiateBooking providing flightName, seatCategory. Ticket amt is deducted from customer account
3. Airline then updates the flight status to on-time (only one time activity)
4. Airline then confirms the booking

Steps from 2 to 4 needs to be performed for every booking

B. Airling cancels flight
1. Airline first needs to know the total amount(ethers) it needs to refund using getFlightCancellationRefundValue
2. Airline then needs to set this refund value as msg.value and call cancelFlight.

C. Customer cancels booking