# LADHARI Steam - Spring Boot Microservices

## Description

This project is a microservices-based architecture built using Spring Boot, inspired by platforms like Steam. Its primary goal is to provide users with a platform to browse and purchase games. The architecture is designed for scalability, modularity, and ease of maintenance.

---

## Architectures

### Overview
This platform provides an intuitive way for users to manage their game library, order games, and handle payments. The system is built around key entities and interactions that ensure seamless user experiences.

---

### Features
- **User Registration**: Automatically creates a library for every registered user.
- **Game Library**: Each user has exactly one library, containing all purchased games.
- **Game Ordering**: Users can order multiple games, and the system ensures no duplicate purchases.
- **Payment Processing**: Links payments to orders, with one payment per order.
- **Duplicate Game Check**: Prevents users from purchasing the same game twice.

---

### System Workflow

#### 1. User Registration
- When a user registers on the platform, a library is automatically created for them.
- Each user has only one library associated with their account.

#### 2. Ordering Games
- Users can order one or multiple games.
- The system validates the order:
  - Checks if any of the games in the order already exist in the user's library.
  - If the user already owns a game, the order is canceled, and a message is displayed: "You already own this game."
- If all games in the order are valid, the system creates an order and corresponding order lines.

#### 3. Payment
- Each order generates a single payment entry.
- The system ensures that payment is processed successfully before completing the order.

#### 4. Updating the Library
- Once the payment is confirmed, the games in the order are added to the user's library.
- The library is updated to include the new games.

---

### System Entities

#### User-Service
- **Purpose**: Manages user accounts and registration.
- **Key Action**: Automatically creates a library for each new user.

#### Library-Service
- **Purpose**: Manages the user's game collection.
- **Key Actions**:
  - Automatically creates a library during registration.
  - Updates the library after successful orders.
  - Prevents duplicate games from being added.

#### Orders-Service
- **Purpose**: Manages orders and order lines.
- **Key Actions**:
  - Creates orders and corresponding order lines.
  - Validates that the user does not already own the games being ordered.

#### Payment-Service
- **Purpose**: Handles payments for orders.
- **Key Actions**:
  - Links each payment to a single order.
  - Ensures payments are successful before completing orders.

#### Games-Service
- **Purpose**: Provides details about available games.
- **Key Actions**:
  - Supplies game information to other services.

---

### Key Business Rules
1. **Library Creation**: Each user has exactly one library created during registration.
2. **Order Validation**:
   - An order cannot include games already in the user's library.
   - If a duplicate game is detected, the order is canceled, and the user is notified.
3. **Payment Linking**:
   - Each order is associated with one payment.
   - Orders are only completed after successful payment.
4. **Library Updates**:
   - Upon successful payment, the games in the order are added to the user's library.

---

### Error Handling
- **Duplicate Game in Order**:
  - If the user attempts to order a game already in their library, the order is canceled.
  - A message is displayed: "You already own this game."

### Architecture Diagram

![Architecture Diagram](screens/architecture_final.png)

### Infrastructure Diagram

![Azure Container Apps infrastructure](docs/architecture_azure_cible_finale.svg)

### Class Diagram

![Class Diagram](screens/spring_boot_classdiagram.png)

### Authentication and Authorization Flow

This document describes the authentication and authorization flow in a microservices architecture using an API Gateway. The flow ensures secure communication, proper validation of user credentials, and controlled access to microservices.

#### Flow Steps

1. **Login Request**:  
   The user sends a login request to the User Service, which processes the login and generates a JWT.

2. **API Gateway Validation**:  
   For all subsequent requests, the Front End includes the JWT in the authorization header. The API Gateway validates the JWT for authentication and authorization.

3. **JWT Validation**:  
   If the JWT is valid, the API Gateway forwards the request to the intended service. If invalid, a 401 Unauthorized response is returned.

4. **Request Forwarding**:  
   Upon successful JWT validation, the API Gateway forwards the request to the appropriate service for processing.

#### Summary

This flow is essential for ensuring secure access to microservices. It ensures that only authorized users can access services, and any invalid JWTs result in an appropriate error response.

![Authentication Flow](screens/arch_auth.gif)


---

## Installation

Follow the instructions below to set up the project locally.

### Prerequisites

Make sure you have the following tools installed:

- **Java JDK 17** or later
- **Maven**
- **Docker** and **Docker Compose**
- **PostgreSQL**
- **MongoDB**
- **Angular CLI** (if working with the frontend)

### Steps

1. Clone the repository:

   ```bash
   git clone https://github.com/achrafladhari/UI_Spring
   cd UI_Spring
   ```

2. Build the Spring Boot microservices:

   ```bash
   cd <service-folder>
   mvn clean install
   ```

3. Start the required databases (MongoDB, PostgreSQL) using Docker Compose:

   ```bash
   docker-compose up -d
   ```

   This will start MongoDB and Mongo Express in Docker containers.

4. Run each microservice:

   ```bash
   cd <service-folder>
   mvn spring-boot:run
   ```

5. Example run the API Gateway:

   ```bash
   cd gateway
   mvn spring-boot:run
   ```

6. Run the Angular frontend (if applicable):

   ```bash
   cd UI_Spring
   npm install --force
   ng s
   ```

---

## Usage

### Authentication

All secured routes require a valid JWT token. Obtain the token by authenticating with the `/auth/login` endpoint in the `users` service. The token must be included in the `Authorization` header of all requests to secured endpoints.


### Endpoints

| Service            | Method           | Endpoint                                                 | Description                          | Secured |
| ------------------ | ---------------- | -------------------------------------------------------- | ------------------------------------ | ------- |
| **Category**       | POST, GET        | `localhost:8222/api/v1/category/admin`                   | Manage categories                    | Yes     |
|                    | GET, DELETE, PUT | `localhost:8222/api/v1/category/admin/{category-id}`     | Perform actions on specific category | Yes     |
| **Games**          | POST             | `localhost:8222/api/v1/game/admin`                       | Add a new game                       | Yes     |
|                    | POST             | `localhost:8222/api/v1/games/purchase`                   | Purchase a game                      | Yes     |
|                    | DELETE, PUT      | `localhost:8222/api/v1/game/admin/{game-id}`             | Manage a specific game               | Yes     |
|                    | GET              | `localhost:8222/api/v1/game/pagination`                  | Get paginated list of games          | No      |
|                    | GET              | `localhost:8222/api/v1/game/{game-id}`                   | Get game details                     | No      |
| **Library**        | GET, POST        | `localhost:8222/api/v1/library`                          | Access or modify the library         | Yes     |
|                    | DELETE           | `localhost:8222/api/v1/library/{username}`               | Delete a library by username         | Yes     |
|                    | PUT              | `localhost:8222/api/v1/library/purchase`                 | Update library with a purchase       | Yes     |
| **Orders**         | POST             | `localhost:8222/api/v1/orders`                           | Place an order                       | Yes     |
|                    | GET              | `localhost:8222/api/v1/orders/{username}`                | Get orders for a user                | Yes     |
| **Orders (Admin)** | GET              | `localhost:8222/api/v1/order/admin/{order-id}`           | Get specific order details (admin)   | Yes     |
|                    | GET              | `localhost:8222/api/v1/order/admin`                      | Get all orders (admin)               | Yes     |
| **Order Lines**    | GET              | `localhost:8222/api/v1/order-lines/order/{order-id}`     | Get order lines by order ID          | Yes     |
| **User Service**   | POST             | `localhost:8222/api/v1/auth/login`                       | Authenticate user                    | No      |
|                    | POST             | `localhost:8222/api/v1/auth/register`                    | Register a new user                  | No      |
|                    | GET              | `localhost:8222/api/v1/user/admin/exists/{user-id}`      | Check if user exists                 | Yes     |
|                    | GET              | `localhost:8222/api/v1/user/admin`                       | Get all users (admin)                | Yes     |
|                    | GET              | `localhost:8222/api/v1/user/admin/pagination`            | Get paginated list of users          | Yes     |
|                    | PUT              | `localhost:8222/api/v1/users/update/{user-id}`           | Update user details by ID            | Yes     |
|                    | PUT              | `localhost:8222/api/v1/users/update/username/{username}` | Update user details by username      | Yes     |
|                    | DELETE           | `localhost:8222/api/v1/users/{user-id}`                  | Delete user by ID                    | Yes     |
|                    | GET              | `localhost:8222/api/v1/users/{user-id}`                  | Get user details by ID               | Yes     |
|                    | GET              | `localhost:8222/api/v1/users/username/{user-id}`         | Get user details by username         | Yes     |

### SWAGGER TABLE

The table provides a concise overview of available Swagger endpoints for various services within a system. Each row lists a service name, the HTTP method (all being "SWAGGER" in this case), the specific endpoint URL, and whether the endpoint is secured. None of the endpoints are secured, as indicated in the "Secured" column. These endpoints correspond to the local environment, with URLs pointing to Swagger UI interfaces for managing Users, Games, Library, Orders, and Payments.

| Swager Service Name | Method  | Endpoint                                         | Secured |
| ------------------- | --------| ------------------------------------------------ | ------- |
| **SWGGER USER**     | SWAGGER | `localhost:8222/users/swagger-ui/index.html`     | NO      |
| **SWGGER Games**    | SWAGGER | `localhost:8222/games/swagger-ui/index.html`     | NO      |
| **SWGGER Library**  | SWAGGER | `localhost:8222/library/swagger-ui/index.html`   | NO      |
| **SWGGER Orders**   | SWAGGER | `localhost:8222/order/swagger-ui/index.html`     | NO      |
| **SWGGER Payments** | SWAGGER | `localhost:8222/payment/swagger-ui/index.html`   | NO      |


---

# Docker And Docker Compose
### Docker file for spring boot
![Dockerfile Spring Boot (Backend)](screens/dockerfilebackend.png)
### Docker file for Angular
![Dockerfile Angular (Frontend)](screens/dockerfilefrontend.png)

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)

## Running the Application

```
docker-compose up -d
```
-  Access the application at:
    - API Gateway: http://localhost:8222
    - Eureka Dashboard: http://localhost:8761
## Stopping the Application

```
docker-compose down
```
## Docker compose file
### 1. **Config Server**
- **Port**: 8888
- **Description**: Centralized configuration management service.
- **Health Check**: Checks for availability on port 8888.

### 2. **Discovery Service (Eureka)**
- **Port**: 8761
- **Description**: Service registry to allow microservices to discover each other.
- **Depends On**: Config Server (healthcheck).

### 3. **API Gateway**
- **Port**: 8222
- **Description**: Gateway for routing requests to microservices.
- **Depends On**: Discovery Service (healthcheck).

### 4. **Games Service**
- **Description**: Handles game-related data.
- **Database**: PostgreSQL (connection URL).
- **Depends On**: API Gateway (healthcheck).

### 5. **Library Service**
- **Description**: Manages the game library.
- **Database**: MongoDB.
- **Depends On**: API Gateway (healthcheck).

### 6. **Order Service**
- **Description**: Handles game orders.
- **Depends On**: API Gateway (healthcheck).

### 7. **Payment Service**
- **Description**: Manages payment processing for orders.
- **Depends On**: API Gateway (healthcheck).

### 8. **User Service**
- **Description**: Manages user data.
- **Database**: MongoDB.
- **Depends On**: API Gateway (healthcheck).

### 9. **Client (UI)**
- **Port**: 80
- **Description**: Frontend UI for interacting with the microservices.
- **Depends On**: User Service.

### 10. **SonarQube**
- **Port**: 9000
- **Description**: Code quality analysis platform.
- **Database**: PostgreSQL (connection URL).

### 11. **MongoDB**
- **Port**: 27017
- **Description**: NoSQL database for services like Library and User.
- **Environment Variables**: Mongo root username and password.

### 12. **Mongo Express**
- **Port**: 8081
- **Description**: Web-based admin interface for MongoDB.
- **Depends On**: MongoDB.

### 13. **PostgreSQL**
- **Port**: 5432
- **Description**: Relational database for services like Games and Orders.
- **Environment Variables**: PostgreSQL username and password.

### 14. **pgAdmin**
- **Port**: 5050
- **Description**: Web-based admin interface for PostgreSQL.
- **Depends On**: PostgreSQL.

### Health Checks

All services have health checks configured to ensure they are running properly. For example:

- **Config Server**: Available on port 8888.
- **Discovery Service (Eureka)**: Available on port 8761.
- **API Gateway**: Available on port 8222.

If any service fails the health check, Docker Compose will attempt to restart the service.

### Volumes

The following volumes are used to persist data across service restarts:

- `mongo`: MongoDB data.
- `postgres`: PostgreSQL data.
- `pgadmin`: pgAdmin data.
- `sonarqube_data`: SonarQube data.
- `sonarqube_extensions`: SonarQube extensions.
- `sonarqube_logs`: SonarQube logs.

### Networks

All services are connected to the `microservices` network, ensuring they can communicate with each other without exposing services externally unless specified.
### Docker compose file
![Docker Compose File](screens/exempledesservices.png)
### Docker Compose Services
![Docker Compose Services](screens/dockercomposeservice.png)
### Docker Compose Network & Volumes
![Docker Network and Volumes](screens/networks&volumes.png)
## Application Test in local
### Admin
#### CRUD Category
![CRUD Category](screens/crud_category_admin_local.png)
#### CRUD Games
![CRUD Games](screens/crud_games_local.png)
#### CRUD Users
![CRUD Users](screens/crud_users_local.png)
### User
#### Market test local
![Market local](screens/market_test_local.png)
#### Inventory list
![Inventory List](screens/inventory_list_local.png)
#### Order list
![Order List](screens/order_list_local.png)
#### 404 Page
![404 Page](screens/404_local.png)

---

# CircleCI

The CI/CD definition is versioned in [`.circleci/config.yml`](.circleci/config.yml).
It is intentionally declarative: the executable CI logic is split into versioned scripts under [`.circleci/scripts/`](.circleci/scripts/), which can be checked locally with `bash -n` before a CircleCI run.

## Pipeline flow

Every branch and pull request must pass Trivy source, secret and IaC scans; backend tests with JaCoCo and the SonarQube quality gate; Angular headless tests and a production build; then Docker image build, Trivy image scans, Syft CycloneDX 1.6 SBOM generation and Dependency-Track publication, Docker Compose smoke tests, Eureka registration checks, and a passive OWASP ZAP baseline scan.

On non-`master` branches, the complete container qualification runs against local CI images. On `master`, that same qualification job builds the images once, pushes those already-tested local images to Azure Container Registry, and deploys them to Azure Container Apps after approval.

## CircleCI contexts

Create these organization contexts before enabling the project:

| Context | Variables | Purpose |
| --- | --- | --- |
| `sonarqube` | `SONAR_HOST_URL`, `SONAR_TOKEN` | Runs analysis and waits for the quality gate on the self-hosted SonarQube runner. |
| `dependency-track` | `DTRACK_URL`, `DTRACK_API_KEY`, `DTRACK_PARENT_UUID` | Publishes one CycloneDX 1.6 SBOM per candidate image to the existing Dependency-Track API from the self-hosted runner. |
| `acr-publish` | `ACR_LOGIN_SERVER`, `ACR_USERNAME`, `ACR_PASSWORD` | Grants the `master`-only publication job permission to push to ACR. |

The pipeline generates an ephemeral JWT secret only for Compose validation. Runtime deployments must inject their own secret through a secret manager.

### Private SonarQube runner

The SonarQube jobs and the Dependency-Track SBOM publication job are assigned to the `drghassen/sonar-vm` CircleCI machine runner. This runner is installed on the VM hosting SonarQube and Dependency-Track, so the `sonarqube` context must use a `SONAR_HOST_URL` reachable from that VM. Keep `SONAR_TOKEN` only in the CircleCI context; never commit it to the repository.

### Dependency-Track SBOM publication

Dependency-Track is expected to be running before the pipeline starts. CircleCI does not start or reinstall it. Configure these values in the `dependency-track` CircleCI context:

- `DTRACK_URL`: Dependency-Track API base URL reachable from the `drghassen/sonar-vm` runner, for example `http://172.29.208.5:8080` or `http://localhost:8080`.
- `DTRACK_API_KEY`: dedicated Dependency-Track API key for CircleCI. Do not use admin credentials.
- `DTRACK_PARENT_UUID`: collection project UUID, currently `65d253c6-e059-4b3c-b86e-f5e197852ac6`.

The API key team needs `BOM_UPLOAD`, `PROJECT_CREATION_UPLOAD`, and `VIEW_PORTFOLIO`. `BOM_UPLOAD` accepts SBOM uploads, `PROJECT_CREATION_UPLOAD` allows `autoCreate=true` child project creation during upload, and `VIEW_PORTFOLIO` lets the pipeline validate the configured parent project before publishing. Do not grant broader permissions such as `PORTFOLIO_MANAGEMENT` unless another process requires them. If Dependency-Track portfolio access control is enabled, also assign the team access to the parent collection project.

The SBOM job uses Syft `1.50.0` and writes canonical artifacts as `sbom-reports/<service>/<service>-<IMAGE_TAG>.cdx.json`. The same files are uploaded to Dependency-Track and later attached to ACR images with ORAS.

## ACR image tag

All pushed images use the immutable pipeline image tag:

```text
<ACR_LOGIN_SERVER>/user-service:build-<pipeline.number>
```

No mutable `latest` tag is pushed.

---

## Azure Container Apps deployment

The current production infrastructure is defined in [`ACA/`](ACA/) with Terraform modules for networking, managed data services, identities, the Container Apps environment, application services, Redis, and database migrations.

CircleCI validates Terraform changes automatically. On `master`, the release workflow performs an Azure/OIDC preflight, calculates the deployment plan, waits for manual approval, and then applies the Azure Container Apps deployment serially.

---


# Test Application in production
#### Home Page :
![Home Page](screens/access_app_cloud.png)
#### Register Page :
![Register Page](screens/register_form_cloud.png)
### USER
#### User Account :
![User Account](screens/register_new_user_cloud.png)
#### Game will purchase :
![Game Will purchase](screens/game_added_admin_cloud.png)
#### Game purchased :
![Game Will purchase](screens/puchase_game_cloud.png)
#### Orders Page :
![Orders Page](screens/orders_cloud.png)
#### Inventory Page :
![Inventory Page](screens/inventory_user_cloud.png)
### ADMIN
#### List Categories :
![List Categories](screens/admin_add_category_cloud.png)
#### Add Category :
![Add Category](screens/category_add_cloud.png)
#### Modify Category :
![Modify Category](screens/category_update_cloud.png)
#### Add Game :
![Add Game](screens/game_add_cloud.png)
#### Modify Game :
![Modify Game](screens/update_game_cloud.png)

**PS** : Same thing for the user there is CRUD with ADMIN privileges and the user can update his profile

---

## Technologies

- [Spring Boot](https://spring.io/) - Backend framework
- [Spring Boot Microservices](https://spring.io/microservices) - Microservices
- [Spring Boot Cloud Gateway](https://spring.io/projects/spring-cloud-gateway) - Gateway
- [Spring Boot Reactive Programming](https://spring.io/reactive) - Reactive programming
- [PostgreSQL](https://www.postgresql.org/) - Relational database
- [MongoDB](https://www.mongodb.com/) - NoSQL database
- [Angular](https://angular.io/) - Frontend framework
- [Feign](https://spring.io/projects/spring-cloud-openfeign) - Declarative REST client
- [Eureka](https://spring.io/projects/spring-cloud-netflix) - Service discovery
- [JWT](https://jwt.io/) - Token-based authentication
- [Docker](https://docs.docker.com/) - Containerisation
- [CircleCI](https://circleci.com/docs/) - Pipeline CI/CD
- [Terraform](https://developer.hashicorp.com/terraform/docs) - Build infrastructure
- [Prometheus](https://prometheus.io/docs/introduction/overview/) - Metrics
- [Grafana](https://grafana.com/docs/) - Dashboards
- [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/) - Cloud runtime

---

Achraf BEN CHEIKH LADHARI. © 2024 All rights reserved.
