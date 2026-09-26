# Réseau minimal et sans coût fixe : un VPC dédié, un sous-réseau public, une passerelle
# Internet. Pas de passerelle NAT (≈ 35 $/mois) : le serveur est seul, en sous-réseau public,
# protégé par son groupe de sécurité (80/443 uniquement) et administré par SSM.

data "aws_availability_zones" "disponibles" {
  state = "available"
}

resource "aws_vpc" "principal" {
  cidr_block           = var.cidr_vpc
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.nom}-vpc" }
}

resource "aws_internet_gateway" "principal" {
  vpc_id = aws_vpc.principal.id
  tags   = { Name = "${var.nom}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.principal.id
  cidr_block              = cidrsubnet(var.cidr_vpc, 8, 1)
  availability_zone       = data.aws_availability_zones.disponibles.names[0]
  map_public_ip_on_launch = false # IP publique fixe portée par l'Elastic IP du serveur
  tags                    = { Name = "${var.nom}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.principal.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.principal.id
  }
  tags = { Name = "${var.nom}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Le groupe de sécurité par défaut du VPC n'autorise plus rien (bonne pratique CIS).
resource "aws_default_security_group" "verrouille" {
  vpc_id = aws_vpc.principal.id
  tags   = { Name = "${var.nom}-defaut-verrouille" }
}
