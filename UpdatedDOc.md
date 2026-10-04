Activity


GET
/activity-logs
Get activity logs

Parameters
Try it out
Name	Description
page
integer
(query)
page
limit
integer
(query)
limit
startDate
string($date)
(query)
startDate
endDate
string($date)
(query)
endDate
action
string
(query)
action
userId
string
(query)
userId
Responses
Code	Description	Links
200	
List of activity logs

Assignments


POST
/assignments
Assign tasks to users

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "taskIds": [
    "3fa85f64-5717-4562-b3fc-2c963f66afa6"
  ],
  "userIds": [
    "3fa85f64-5717-4562-b3fc-2c963f66afa6"
  ]
}
Responses
Code	Description	Links
201	
Assignments created

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": [
    {}
  ]
}
No links
400	
Bad request

No links
404	
Task or user not found

No links
500	
Server error

No links

GET
/assignments/{taskId}
Get assignments for a task

Parameters
Try it out
Name	Description
taskId *
string($uuid)
(path)
taskId
Responses
Code	Description	Links
200	
List of assignments

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": [
    {}
  ]
}
No links
401	
Unauthorized

No links
500	
Server error

No links

DELETE
/assignments/{assignmentId}
Remove an assignment

Parameters
Try it out
Name	Description
assignmentId *
string($uuid)
(path)
assignmentId
Responses
Code	Description	Links
200	
Assignment removed

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true
}
No links
404	
Assignment not found

No links
500	
Server error

Auth


POST
/auth/register
Register a new business and admin user

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "businessName": "string",
  "businessEmail": "user@example.com",
  "adminName": "string",
  "adminEmail": "user@example.com",
  "password": "string",
  "businessIndustry": "string"
}
Responses
Code	Description	Links
200	
Registration successful

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "message": "string",
  "businessId": "string"
}
No links
400	
Bad request

No links

POST
/auth/verify-otp
Verify email with OTP

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "email": "user@example.com",
  "otpCode": "string"
}
Responses
Code	Description	Links
200	
Email verified successfully

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "token": "string",
  "userId": "string",
  "businessId": "string"
}
No links
400	
Invalid code or email

No links

POST
/auth/forgot-password
Request password reset

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "email": "user@example.com"
}
Responses
Code	Description	Links
200	
Password reset OTP sent

No links
400	
User not found

No links

POST
/auth/verify-reset-otp
Verify password reset OTP

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "email": "user@example.com",
  "otpCode": "string"
}
Responses
Code	Description	Links
200	
OTP verified

No links
400	
Invalid code

No links

POST
/auth/reset-password
Reset password

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "email": "user@example.com",
  "otpCode": "string",
  "newPassword": "string"
}
Responses
Code	Description	Links
200	
Password reset successfully

No links
400	
Invalid code or password

No links

POST
/auth/resend-otp
Resend OTP

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "email": "user@example.com"
}
Responses
Code	Description	Links
200	
OTP resent successfully

No links
400	
User not found

No links

POST
/auth/login
Login user

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "email": "user@example.com",
  "password": "string"
}
Responses
Code	Description	Links
200	
Login successful

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "token": "string",
  "user": {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "businessId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "name": "string",
    "email": "user@example.com",
    "role": "admin",
    "status": "active",
    "emailVerified": true,
    "joinedAt": "2026-06-02T10:27:05.756Z",
    "lastLogin": "2026-06-02T10:27:05.756Z",
    "createdAt": "2026-06-02T10:27:05.756Z",
    "updatedAt": "2026-06-02T10:27:05.756Z"
  },
  "business": {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "name": "string",
    "email": "user@example.com",
    "industry": "string",
    "logoUrl": "string",
    "createdAt": "2026-06-02T10:27:05.756Z",
    "updatedAt": "2026-06-02T10:27:05.756Z"
  }
}
No links
401	
Invalid credentials

Comments


GET
/comments/{taskId}
Get comments for a task

Parameters
Try it out
Name	Description
taskId *
string($uuid)
(path)
Task ID

taskId
Responses
Code	Description	Links
200	
List of comments

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": [
    {
      "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "content": "string",
      "userId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "createdAt": "2026-06-02T10:27:43.819Z"
    }
  ]
}
No links
500	
Server error

No links

POST
/comments
Create a new comment

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "taskId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "content": "string",
  "parentCommentId": "3fa85f64-5717-4562-b3fc-2c963f66afa6"
}
Responses
Code	Description	Links
200	
Comment created

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6"
  }
}
No links
400	
Bad request

No links

DELETE
/comments/{commentId}
Delete a comment

Parameters
Try it out
Name	Description
commentId *
string($uuid)
(path)
commentId
Responses
Code	Description	Links
200	
Comment deleted

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true
}
No links
404	
Comment not found

No links
500	
Server error

No links

PUT
/comments/{commentId}/reaction
Toggle reaction on a comment

Parameters
Try it out
Name	Description
commentId *
string($uuid)
(path)
commentId
Request body

application/json
Example Value
Schema
{
  "type": "like"
}
Responses
Code	Description	Links
200	
Reaction updated

No links
400	
Invalid reaction type

No links
404	
Comment not found

No links
Dashboard


GET
/dashboard/metrics
Get dashboard metrics

Parameters
Try it out
Name	Description
memberId
string
(query)
Optional member ID to filter metrics

memberId
Responses
Code	Description	Links
200	
Dashboard metrics

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": {}
}
No links
401	
Unauthorized

No links
500	
Server error

Epics


GET
/epics
Get all epics

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
List of epics

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": [
    {
      "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "name": "string",
      "description": "string",
      "status": "string"
    }
  ]
}
No links
500	
Server error

No links

POST
/epics
Create a new epic

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "name": "string",
  "description": "string"
}
Responses
Code	Description	Links
200	
Epic created

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "name": "string"
  }
}
No links
400	
Bad request

No links

POST
/epics/{epicId}/link-tasks
Link tasks to an epic

Parameters
Try it out
Name	Description
epicId *
string($uuid)
(path)
epicId
Request body

application/json
Example Value
Schema
{
  "taskIds": [
    "3fa85f64-5717-4562-b3fc-2c963f66afa6"
  ]
}
Responses
Code	Description	Links
200	
Tasks linked successfully

No links
404	
Epic not found

No links

POST
/epics/backfill
Backfill epics from tasks

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
Backfill completed

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "message": "string"
}
No links
500	
Server error

Fees


GET
/fees
View applicable fees

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
List of fees

No links
Ideas


GET
/ideas
Get all ideas

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
List of ideas

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": [
    {
      "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "businessId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "userId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "userName": "string",
      "title": "string",
      "description": "string",
      "status": "under_review",
      "createdAt": "2026-06-02T10:29:27.288Z",
      "updatedAt": "2026-06-02T10:29:27.288Z"
    }
  ]
}
No links

POST
/ideas
Create a new idea

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "title": "string",
  "description": "string"
}
Responses
Code	Description	Links
201	
Idea created

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "businessId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "userId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "userName": "string",
    "title": "string",
    "description": "string",
    "status": "under_review",
    "createdAt": "2026-06-02T10:29:27.299Z",
    "updatedAt": "2026-06-02T10:29:27.299Z"
  }
}
No links
400	
Invalid input

No links
401	
Unauthorized

No links
500	
Server error

No links

PUT
/ideas/{id}/status
Update idea status

Parameters
Try it out
Name	Description
id *
string
(path)
id
Request body

application/json
Example Value
Schema
{
  "status": "under_review"
}
Responses
Code	Description	Links
200	
Status updated

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": {}
}
No links
403	
Forbidden (Admin/Manager only)

No links
404	
Idea not found

No links
500	
Server error

No links

PUT
/ideas/{id}
Update an idea (title and description)

Parameters
Try it out
Name	Description
id *
string
(path)
id
Request body

application/json
Example Value
Schema
{
  "title": "string",
  "description": "string"
}
Responses
Code	Description	Links
200	
Idea updated

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "businessId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "userId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "userName": "string",
    "title": "string",
    "description": "string",
    "status": "under_review",
    "createdAt": "2026-06-02T10:29:27.339Z",
    "updatedAt": "2026-06-02T10:29:27.339Z"
  }
}
No links
404	
Idea not found

No links
500	
Server error

No links

DELETE
/ideas/{id}
Delete an idea

Parameters
Try it out
Name	Description
id *
string
(path)
id
Responses
Code	Description	Links
200	
Idea deleted

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true
}
No links
404	
Idea not found

No links
500	
Server error

No links
KYC


GET
/kyc/status
Get KYC status for current user and business

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
KYC status details

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "user": {
    "bvnStatus": "pending",
    "ninStatus": "pending",
    "rejection_reason": "string"
  },
  "business": {
    "status": "pending",
    "rejection_reason": "string"
  }
}
No links

POST
/kyc/initiate
Initiate KYC verification (BVN or NIN)

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "type": "bvn",
  "number": "string"
}
Responses
Code	Description	Links
200	
Verification initiated, OTP sent if applicable

No links

POST
/kyc/verify-otp
Verify OTP to complete KYC

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "otp": "string"
}
Responses
Code	Description	Links
200	
KYC completed successfully

No links

POST
/kyc/business
Submit Business KYC (Address, Proof of Address)

Parameters
Try it out
No parameters

Request body

multipart/form-data
proof_of_address
string($binary)
country
string
state
string
city
string
street
string
house_number
string
Responses
Code	Description	Links
200	
Business KYC submitted




They're so many missing screens on this project, please check and update accordingly.
See api doc above, locate correspondent screens and adjust accordingly.

Upon login, there should be a KYC check to confirm if user is verified, for BVN and NIN, else if not verified, navigate user to KYC page to verify their BVN and NIN. before user can access the dashboard.

KYC is on 3 tier levels, Tier 1 is either BVN or NIN, Tier 2 is also either BVN or NIN, then tier 3 is proof of address, tier 1 and 2 is mandated before a user could access the dashboard.

See the endpoint above for neccessary adjustment to be done on the home page and other screens.

On Wallet page see the complete endpoint below, check user KYC status always on tap wallet screen, if user is on Tier 1 and 2, personal wallet is automatically generated for them, there can view the wallet and virtual account information. Business wallet should be locked if user hasn't verify their Proof of address, so if check on KYC status and proof of address is pending, lock the business wallet and inform a user to click to submit proof of address in order to create a business virtual account, on tab, take user to proof of address interface, after proof of address is submitted, and status indicate verified, before user can proceed to create business virtual account, see the endpoint below.

For the Payroll see complete endpoint below, likewise tasks, backlog, ideas, product doc etc see the updated endpoints below and update accordingly.

Also I don't like the UI style, isn't looking smart and professional, add back button to activity page and all other inner page where button tab isn't active.

I didn't see the icon for the biometric on login page, I didn't see the options on settings page to toogle ON/OFF biometric.

Use rubik font across the app.


Payroll


POST
/payroll/adjustments
Add a payroll adjustment (bonus or deduction)

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "userId": "string",
  "type": "bonus",
  "amount": 0,
  "currency": "USD",
  "reason": "string"
}
Responses
Code	Description	Links
200	
Adjustment added

No links

GET
/payroll/adjustments
Get pending payroll adjustments

Parameters
Try it out
Name	Description
userId
string
(query)
userId
Responses
Code	Description	Links
200	
List of adjustments

No links

DELETE
/payroll/adjustments/{id}
Delete/Cancel a pending adjustment

Parameters
Try it out
Name	Description
id *
string
(path)
id
Responses
Code	Description	Links
200	
Adjustment deleted

No links

GET
/payroll/summary
Get payroll summary for all team members

Parameters
Try it out
Name	Description
search
string
(query)
Search by name or email

search
role
string
(query)
Filter by user role

role
startDate
string($date)
(query)
Filter adjustments start date (YYYY-MM-DD)

startDate
endDate
string($date)
(query)
Filter adjustments end date (YYYY-MM-DD)

endDate
page
integer
(query)
Page number

Default value : 1

1
limit
integer
(query)
Items per page

Default value : 10

10
Responses
Code	Description	Links
200	
List of team members with payroll calculations

No links

PUT
/payroll/user/{id}
Update user payroll details

Parameters
Try it out
Name	Description
id *
string
(path)
id
Request body

application/json
Example Value
Schema
{
  "salary": 0,
  "salary_currency": "string",
  "bank_account_number": "string",
  "bank_code": "string",
  "account_name": "string",
  "contract_start_date": "2026-06-02"
}
Responses
Code	Description	Links
200	
User payroll details updated

No links

GET
/payroll/config
Get payroll configuration (salary interval)

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
Current payroll configuration

No links

PUT
/payroll/config
Update payroll configuration

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "salary_interval": "daily",
  "salary_custom_date": "2026-06-02T10:44:53.334Z"
}
Responses
Code	Description	Links
200	
Configuration updated

No links
Product Documentation


POST
/ideas/{ideaId}/documentation
Generate product documentation for an idea

Parameters
Try it out
Name	Description
ideaId *
string
(path)
ideaId
Responses
Code	Description	Links
201	
Documentation generated successfully

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "businessId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "ideaId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "title": "string",
    "content": "string",
    "logoUrl": "string",
    "createdBy": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "createdAt": "2026-06-02T10:44:53.337Z",
    "updatedAt": "2026-06-02T10:44:53.337Z"
  }
}
No links

GET
/ideas/{ideaId}/documentation
Get all product documentation for an idea

Parameters
Try it out
Name	Description
ideaId *
string
(path)
ideaId
Responses
Code	Description	Links
200	
List of product documentation

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": [
    {
      "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "businessId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "ideaId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "title": "string",
      "content": "string",
      "logoUrl": "string",
      "createdBy": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "createdAt": "2026-06-02T10:44:53.340Z",
      "updatedAt": "2026-06-02T10:44:53.340Z"
    }
  ]
}
No links

PUT
/product-documentation/{id}
Update product documentation

Parameters
Try it out
Name	Description
id *
string
(path)
id
Request body

multipart/form-data
content
string
logo
string($binary)
Responses
Code	Description	Links
200	
Documentation updated

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "businessId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "ideaId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "title": "string",
    "content": "string",
    "logoUrl": "string",
    "createdBy": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "createdAt": "2026-06-02T10:44:53.344Z",
    "updatedAt": "2026-06-02T10:44:53.344Z"
  }
}
No links

DELETE
/product-documentation/{id}
Delete product documentation

Parameters
Try it out
Name	Description
id *
string
(path)
id
Responses
Code	Description	Links
200	
Documentation deleted

No links

POST
/product-documentation/{id}/regenerate
Regenerate product documentation

Parameters
Try it out
Name	Description
id *
string
(path)
id
Request body

application/json
Example Value
Schema
{
  "areasOfConcern": "string"
}
Responses
Code	Description	Links
200	
Documentation regenerated

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "businessId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "ideaId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "title": "string",
    "content": "string",
    "logoUrl": "string",
    "createdBy": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "createdAt": "2026-06-02T10:44:53.351Z",
    "updatedAt": "2026-06-02T10:44:53.351Z"
  }
}
No links

GET
/product-documentation/{id}/pdf
Download product documentation as PDF

Parameters
Try it out
Name	Description
id *
string
(path)
id
Responses
Code	Description	Links
200	
PDF file

Media type

application/pdf
Controls Accept header.
Example Value
Schema
string

Settings


GET
/settings
Get business settings

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
Business settings details

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "settings": {
    "id": "string",
    "name": "string",
    "email": "string",
    "phone_number": "string",
    "industry": "string",
    "logo_url": "string",
    "currency": "string"
  }
}
No links

PUT
/settings
Update business settings (e.g., currency)

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "currency": "USD",
  "name": "string",
  "industry": "string",
  "logo_url": "string"
}
Responses
Code	Description	Links
200	
Settings updated

No links

POST
/settings/update-contact/request-otp
Request OTP to update business email or phone number

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "type": "email",
  "value": "string"
}
Responses
Code	Description	Links
200	
OTP sent successfully

No links
400	
Invalid input

No links

POST
/settings/update-contact/verify-otp
Verify OTP and update business email or phone number

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "otp": "string"
}
Responses
Code	Description	Links
200	
Contact updated successfully

No links
400	
Invalid OTP or expired

No links

PUT
/settings/otp-preference
Update transaction OTP preference

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "preference": "email"
}
Responses
Code	Description	Links
200	
Preference updated

No links

GET
/settings/otp-preference
Get transaction OTP preference

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
Current preference

No links
Subscription


GET
/subscription/transactions/export
Export transactions to CSV

Parameters
Try it out
Name	Description
startDate
string($date)
(query)
Start date (YYYY-MM-DD)

startDate
endDate
string($date)
(query)
End date (YYYY-MM-DD)

endDate
Responses
Code	Description	Links
200	
CSV file

Media type

text/csv
Controls Accept header.
Example Value
Schema
string
No links
401	
Unauthorized

No links
500	
Server error

No links

GET
/subscription/transactions
Get subscription transaction history

Parameters
Try it out
Name	Description
page
integer
(query)
Page number

page
perPage
integer
(query)
Items per page

perPage
startDate
string($date)
(query)
Filter by start date

startDate
endDate
string($date)
(query)
Filter by end date

endDate
status
string
(query)
Filter by status

status
Responses
Code	Description	Links
200	
List of transactions

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "transactions": [
    {
      "id": "string",
      "amount": 0,
      "currency": "string",
      "status": "string",
      "type": "string",
      "transaction_type": "string",
      "created_at": "string"
    }
  ],
  "data": [
    {
      "id": "string",
      "amount": 0,
      "currency": "string",
      "status": "string",
      "reference": "string",
      "created_at": "2026-06-02T10:51:50.460Z"
    }
  ],
  "pagination": {
    "total": 0,
    "page": 0,
    "perPage": 0,
    "totalPages": 0
  }
}
No links
401	
Unauthorized

No links
500	
Server error

No links

GET
/subscription/current
Get current subscription

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
Current subscription details

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "subscription": {
    "id": "string",
    "name": "string",
    "plan_name": "string",
    "next_due_subscription_date": "2026-06-02T10:51:50.469Z"
  }
}
No links
500	
Server error

No links

GET
/subscription/cards
Get all payment cards

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
List of payment cards

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "cards": [
    {
      "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "last4": "string",
      "card_type": "string",
      "exp_month": "string",
      "exp_year": "string",
      "is_active": true
    }
  ]
}
No links
500	
Server error

No links

GET
/subscription/plans
Get all pricing plans

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
List of pricing plans

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "plans": [
    {
      "id": "string",
      "name": "string",
      "price": 0,
      "currency": "string",
      "duration": "string",
      "features": [
        "string"
      ]
    }
  ]
}
No links
500	
Server error

No links

POST
/subscription/cards/initiate
Initiate adding a new card

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
Card addition initiated

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "checkout_url": "string"
}
No links
401	
Unauthorized

No links
500	
Server error

No links

DELETE
/subscription/cards/{id}
Remove a payment card

Parameters
Try it out
Name	Description
id *
string($uuid)
(path)
id
Responses
Code	Description	Links
200	
Card removed

No links
404	
Card not found

No links
500	
Server error

No links

PUT
/subscription/cards/{id}/active
Set a card as active for subscription

Parameters
Try it out
Name	Description
id *
string($uuid)
(path)
id
Responses
Code	Description	Links
200	
Card set as active

No links
404	
Card not found

No links
500	
Server error

No links

POST
/subscription/initiate-payment
Initiate a payment

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "planId": "string",
  "currency": "NGN"
}
Responses
Code	Description	Links
200	
Payment initiated

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "checkout_url": "string"
}
No links
401	
Unauthorized

No links
404	
Plan not found

No links
500	
Server error

No links

POST
/subscription/verify-payment
Verify a payment (Subscription or Card Addition)

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "reference": "string"
}
Responses
Code	Description	Links
200	
Payment verified

No links
404	
Transaction not found

No links
500	
Server error

No links

POST
/subscription/downgrade
Downgrade to free plan

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
Downgraded successfully

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "message": "string"
}
No links
401	
Unauthorized

No links
403	
Trial exhausted

No links
500	
Server error

No links

POST
/subscription/cancel
Cancel subscription

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
Subscription cancelled

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "message": "string"
}
No links
400	
No active subscription

No links
401	
Unauthorized

No links
500	
Server error

No links

POST
/subscription/cron/process-renewals
Process subscription renewals (Cron)

Parameters
Try it out
Name	Description
x-cron-secret
string
(header)
x-cron-secret
Responses
Code	Description	Links
200	
Renewals processed

No links
401	
Unauthorized

No links
Tasks


GET
/tasks
Get all tasks

Parameters
Try it out
Name	Description
page
integer
(query)
Page number

page
limit
integer
(query)
Number of items per page

limit
status
string
(query)
Filter by task status

status
Responses
Code	Description	Links
200	
List of tasks

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": {
    "tasks": [
      {
        "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "businessId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "createdBy": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "title": "string",
        "description": "string",
        "status": "pending",
        "startDate": "2026-06-02",
        "endDate": "2026-06-02",
        "dueDate": "2026-06-02",
        "targetValue": 0,
        "accomplishedValue": 0,
        "epic": "string",
        "epicId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "sprint": "string",
        "isOverdue": true,
        "assignedTo": [
          "3fa85f64-5717-4562-b3fc-2c963f66afa6"
        ],
        "attachments": [
          {
            "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
            "taskId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
            "fileName": "string",
            "fileType": "string",
            "fileSize": 0,
            "fileUrl": "string",
            "isImage": true,
            "uploadedBy": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
            "createdAt": "2026-06-02T10:51:50.606Z"
          }
        ],
        "comments": [
          {
            "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
            "taskId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
            "epicId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
            "epicName": "string",
            "userId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
            "userName": "string",
            "userEmail": "user@example.com",
            "parentCommentId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
            "content": "string",
            "mentions": [
              {
                "type": "user",
                "id": "string"
              }
            ],
            "replies": [
              "string"
            ],
            "reactions": [
              {
                "userId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
                "userName": "string",
                "type": "like"
              }
            ],
            "createdAt": "2026-06-02T10:51:50.606Z",
            "updatedAt": "2026-06-02T10:51:50.606Z"
          }
        ],
        "images": [
          "string"
        ],
        "createdAt": "2026-06-02T10:51:50.606Z",
        "updatedAt": "2026-06-02T10:51:50.606Z"
      }
    ],
    "total": 0,
    "epicCounts": {}
  }
}
No links
500	
Server error

No links

POST
/tasks
Create a new task

Parameters
Try it out
No parameters

Request body
application/json
Example Value
Schema
{
  "title": "string",
  "description": "string",
  "epic": "string",
  "epicId": "string",
  "sprint": "string",
  "startDate": "2026-06-02",
  "endDate": "2026-06-02",
  "dueDate": "2026-06-02",
  "assignedTo": [
    "string"
  ]
}
Responses
Code	Description	Links
201	
Task created

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "businessId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "createdBy": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "title": "string",
    "description": "string",
    "status": "pending",
    "startDate": "2026-06-02",
    "endDate": "2026-06-02",
    "dueDate": "2026-06-02",
    "targetValue": 0,
    "accomplishedValue": 0,
    "epic": "string",
    "epicId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "sprint": "string",
    "isOverdue": true,
    "assignedTo": [
      "3fa85f64-5717-4562-b3fc-2c963f66afa6"
    ],
    "attachments": [
      {
        "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "taskId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "fileName": "string",
        "fileType": "string",
        "fileSize": 0,
        "fileUrl": "string",
        "isImage": true,
        "uploadedBy": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "createdAt": "2026-06-02T10:51:50.628Z"
      }
    ],
    "comments": [
      {
        "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "taskId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "epicId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "epicName": "string",
        "userId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "userName": "string",
        "userEmail": "user@example.com",
        "parentCommentId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "content": "string",
        "mentions": [
          {
            "type": "user",
            "id": "string"
          }
        ],
        "replies": [
          "string"
        ],
        "reactions": [
          {
            "userId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
            "userName": "string",
            "type": "like"
          }
        ],
        "createdAt": "2026-06-02T10:51:50.628Z",
        "updatedAt": "2026-06-02T10:51:50.628Z"
      }
    ],
    "images": [
      "string"
    ],
    "createdAt": "2026-06-02T10:51:50.628Z",
    "updatedAt": "2026-06-02T10:51:50.628Z"
  }
}
No links
400	
Invalid input

No links

POST
/tasks/bulk
Bulk create tasks

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "tasks": [
    {
      "title": "string",
      "description": "string",
      "epic": "string",
      "sprint": "string",
      "startDate": "2026-06-02",
      "endDate": "2026-06-02"
    }
  ]
}
Responses
Code	Description	Links
201	
Tasks created

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": [
    {
      "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "businessId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "createdBy": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "title": "string",
      "description": "string",
      "status": "pending",
      "startDate": "2026-06-02",
      "endDate": "2026-06-02",
      "dueDate": "2026-06-02",
      "targetValue": 0,
      "accomplishedValue": 0,
      "epic": "string",
      "epicId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "sprint": "string",
      "isOverdue": true,
      "assignedTo": [
        "3fa85f64-5717-4562-b3fc-2c963f66afa6"
      ],
      "attachments": [
        {
          "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "taskId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "fileName": "string",
          "fileType": "string",
          "fileSize": 0,
          "fileUrl": "string",
          "isImage": true,
          "uploadedBy": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "createdAt": "2026-06-02T10:51:50.650Z"
        }
      ],
      "comments": [
        {
          "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "taskId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "epicId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "epicName": "string",
          "userId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "userName": "string",
          "userEmail": "user@example.com",
          "parentCommentId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "content": "string",
          "mentions": [
            {
              "type": "user",
              "id": "string"
            }
          ],
          "replies": [
            "string"
          ],
          "reactions": [
            {
              "userId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
              "userName": "string",
              "type": "like"
            }
          ],
          "createdAt": "2026-06-02T10:51:50.650Z",
          "updatedAt": "2026-06-02T10:51:50.650Z"
        }
      ],
      "images": [
        "string"
      ],
      "createdAt": "2026-06-02T10:51:50.650Z",
      "updatedAt": "2026-06-02T10:51:50.650Z"
    }
  ]
}
No links
400	
Invalid input

No links
500	
Server error

No links

PATCH
/tasks/bulk
Bulk update tasks

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "taskIds": [
    "string"
  ],
  "updates": {}
}
Responses
Code	Description	Links
200	
Tasks updated

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": [
    {
      "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "businessId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "createdBy": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "title": "string",
      "description": "string",
      "status": "pending",
      "startDate": "2026-06-02",
      "endDate": "2026-06-02",
      "dueDate": "2026-06-02",
      "targetValue": 0,
      "accomplishedValue": 0,
      "epic": "string",
      "epicId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "sprint": "string",
      "isOverdue": true,
      "assignedTo": [
        "3fa85f64-5717-4562-b3fc-2c963f66afa6"
      ],
      "attachments": [
        {
          "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "taskId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "fileName": "string",
          "fileType": "string",
          "fileSize": 0,
          "fileUrl": "string",
          "isImage": true,
          "uploadedBy": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "createdAt": "2026-06-02T10:51:50.670Z"
        }
      ],
      "comments": [
        {
          "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "taskId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "epicId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "epicName": "string",
          "userId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "userName": "string",
          "userEmail": "user@example.com",
          "parentCommentId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
          "content": "string",
          "mentions": [
            {
              "type": "user",
              "id": "string"
            }
          ],
          "replies": [
            "string"
          ],
          "reactions": [
            {
              "userId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
              "userName": "string",
              "type": "like"
            }
          ],
          "createdAt": "2026-06-02T10:51:50.670Z",
          "updatedAt": "2026-06-02T10:51:50.670Z"
        }
      ],
      "images": [
        "string"
      ],
      "createdAt": "2026-06-02T10:51:50.670Z",
      "updatedAt": "2026-06-02T10:51:50.670Z"
    }
  ]
}
No links
400	
Invalid input

No links

DELETE
/tasks/{id}
Delete a task

Parameters
Try it out
Name	Description
id *
string($uuid)
(path)
id
Responses
Code	Description	Links
200	
Task deleted

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true
}
No links
404	
Task not found

No links
500	
Server error

No links
Team


GET
/team/ranking
Get team ranking based on completed tasks

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
Team ranking list

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": [
    {
      "id": "string",
      "name": "string",
      "email": "string",
      "role": "string",
      "completedTasks": 0
    }
  ]
}
No links
500	
Server error

No links

GET
/team/ranking/top
Get top 3 team members based on completed tasks

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
Top 3 team members

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": [
    {
      "id": "string",
      "name": "string",
      "email": "string",
      "role": "string",
      "completedTasks": 0
    }
  ]
}
No links
500	
Server error

No links

GET
/team
Get all team members

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
List of team members

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": [
    {
      "id": "string",
      "name": "string",
      "email": "string",
      "role": "string",
      "status": "string",
      "kyc_status": "string",
      "salary": 0,
      "salary_currency": "string",
      "bank_code": "string",
      "account_number": "string",
      "account_name": "string"
    }
  ]
}
No links
500	
Server error

No links

POST
/team/invite
Invite a new team member

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "name": "string",
  "email": "user@example.com",
  "role": "admin"
}
Responses
Code	Description	Links
200	
Invitation sent

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "message": "string"
}
No links
400	
Bad request

No links

POST
/team/accept-invite/{token}
Accept team invitation

Parameters
Try it out
Name	Description
token *
string
(path)
token
Request body

application/json
Example Value
Schema
{
  "password": "string"
}
Responses
Code	Description	Links
200	
Invitation accepted

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "businessId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "name": "string",
    "email": "user@example.com",
    "role": "admin",
    "status": "active",
    "emailVerified": true,
    "joinedAt": "2026-06-02T10:51:50.741Z",
    "lastLogin": "2026-06-02T10:51:50.741Z",
    "createdAt": "2026-06-02T10:51:50.741Z",
    "updatedAt": "2026-06-02T10:51:50.741Z"
  }
}
No links
400	
Invalid or expired token

No links

GET
/team/verify-invite/{token}
Verify invitation token

Parameters
Try it out
Name	Description
token *
string
(path)
token
Responses
Code	Description	Links
200	
Token is valid

No links
400	
Invalid or expired token

No links

GET
/team/{id}
Get team member by ID

Parameters
Try it out
Name	Description
id *
string
(path)
id
Responses
Code	Description	Links
200	
Team member details

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "businessId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "name": "string",
    "email": "user@example.com",
    "role": "admin",
    "status": "active",
    "emailVerified": true,
    "joinedAt": "2026-06-02T10:51:50.760Z",
    "lastLogin": "2026-06-02T10:51:50.760Z",
    "createdAt": "2026-06-02T10:51:50.760Z",
    "updatedAt": "2026-06-02T10:51:50.760Z"
  }
}
No links
404	
Team member not found

No links

DELETE
/team/{id}
Remove a team member

Parameters
Try it out
Name	Description
id *
string
(path)
id
Responses
Code	Description	Links
200	
Team member removed

No links
404	
Team member not found

No links

PATCH
/team/{id}/status
Update team member status

Parameters
Try it out
Name	Description
id *
string
(path)
id
Request body

application/json
Example Value
Schema
{
  "status": "active"
}
Responses
Code	Description	Links
200	
Status updated

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "businessId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "name": "string",
    "email": "user@example.com",
    "role": "admin",
    "status": "active",
    "emailVerified": true,
    "joinedAt": "2026-06-02T10:51:50.787Z",
    "lastLogin": "2026-06-02T10:51:50.787Z",
    "createdAt": "2026-06-02T10:51:50.787Z",
    "updatedAt": "2026-06-02T10:51:50.787Z"
  }
}
No links
404	
Team member not found

No links

PATCH
/team/{id}/role
Update team member role

Parameters
Try it out
Name	Description
id *
string
(path)
id
Request body

application/json
Example Value
Schema
{
  "role": "admin"
}
Responses
Code	Description	Links
200	
Role updated

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "businessId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "name": "string",
    "email": "user@example.com",
    "role": "admin",
    "status": "active",
    "emailVerified": true,
    "joinedAt": "2026-06-02T10:51:50.808Z",
    "lastLogin": "2026-06-02T10:51:50.809Z",
    "createdAt": "2026-06-02T10:51:50.809Z",
    "updatedAt": "2026-06-02T10:51:50.809Z"
  }
}
No links
404	
Team member not found

No links
Transfers


POST
/api/transfers/account-lookup
Lookup account details

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "bank_code": "string",
  "account_number": "string"
}
Responses
Code	Description	Links
200	
Account details

No links
400	
Bad request

No links

POST
/api/transfers/bulk
Initiate bulk transfer

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "transfers": [
    {
      "recipient_account": "string",
      "recipient_bank": "string",
      "recipient_name": "string",
      "amount": 0,
      "remark": "string",
      "source_type": "string",
      "source_id": "string"
    }
  ]
}
Responses
Code	Description	Links
200	
Transfers queued

No links

GET
/api/transfers
Get transfer history

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
List of transfers

No links

POST
/api/transfers/{id}/retry
Retry a failed transfer

Parameters
Try it out
Name	Description
id *
string
(path)
id
Responses
Code	Description	Links
200	
Transfer retried

No links

POST
/transfers/otp/request
Request OTP for transfer authorization

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "wallet_id": "string"
}
Responses
Code	Description	Links
200	
OTP sent

No links

POST
/transfers/single
Initiate a single transfer

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "bankCode": "string",
  "accountNumber": "string",
  "accountName": "string",
  "amount": 0,
  "remark": "string",
  "otp": "string",
  "wallet_id": "string"
}
Responses
Code	Description	Links
200	
Transfer queued

No links

POST
/transfers/bulk
Initiate a bulk transfer

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "type": "manual",
  "otp": "string",
  "source_wallet_id": "string",
  "data": {}
}
Responses
Code	Description	Links
200	
Transfers queued

No links

GET
/transfers
Get transfer queue

Parameters
Try it out
Name	Description
search
string
(query)
Search by recipient name, account or reference

search
status
string
(query)
Filter by status

Available values : pending, processing, success, failed


--
startDate
string($date)
(query)
Filter by start date (YYYY-MM-DD)

startDate
endDate
string($date)
(query)
Filter by end date (YYYY-MM-DD)

endDate
page
integer
(query)
Page number

Default value : 1

1
limit
integer
(query)
Items per page

Default value : 20

20
Responses
Code	Description	Links
200	
List of transfers

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": [
    {}
  ],
  "pagination": {
    "total": 0,
    "page": 0,
    "limit": 0,
    "totalPages": 0
  }
}
No links

POST
/transfers/{id}/retry
Retry a failed transfer

Parameters
Try it out
Name	Description
id *
string
(path)
id
Responses
Code	Description	Links
200	
Retry initiated

No links

GET
/transfers/banks
Get list of supported banks

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
List of banks

Media type

application/json
Controls Accept header.
Example Value
Schema
{
  "success": true,
  "data": [
    {
      "code": "string",
      "name": "string"
    }
  ]
}
No links

POST
/transfers/lookup
Lookup account name

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "bankCode": "string",
  "accountNumber": "string"
}
Responses
Code	Description	Links
200	
Account details

No links
Wallet


POST
/wallet/create-virtual-account
Retry creation of Virtual Account for User Wallet

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
Virtual Account created successfully

No links

GET
/wallet
Get wallet details (Balance, Virtual Account)

Parameters
Try it out
No parameters

Responses
Code	Description	Links
200	
Wallet details

No links

POST
/wallet/fund/card
Initiate wallet funding via Card

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "amount": 0,
  "wallet_type": "user"
}
Responses
Code	Description	Links
200	
Payment link generated

No links

POST
/wallet/business/create
Create Business Virtual Account (Wallet)

Parameters
Try it out
No parameters

Request body

application/json
Example Value
Schema
{
  "gtb_account_number": "string",
  "business_name": "string"
}
Responses
Code	Description	Links
200	
Business Wallet created

No links

GET
/wallet/verify
Verify payment transaction

Parameters
Try it out
Name	Description
reference *
string
(query)
reference
Responses
Code	Description	Links
200	
Payment verified successfully