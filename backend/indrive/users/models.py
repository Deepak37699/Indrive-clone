from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models
from django.utils.translation import gettext_lazy as _

class CustomUserManager(BaseUserManager):
    def create_user(self, phone_number, password=None, **extra_fields):
        if not phone_number:
            raise ValueError(_('The Phone Number must be set'))
        user = self.model(phone_number=phone_number, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, phone_number, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        extra_fields.setdefault('is_active', True)

        if extra_fields.get('is_staff') is not True:
            raise ValueError(_('Superuser must have is_staff=True.'))
        if extra_fields.get('is_superuser') is not True:
            raise ValueError(_('Superuser must have is_superuser=True.'))
        return self.create_user(phone_number, password, **extra_fields)

class User(AbstractUser):
    username = None # We will use phone_number as the unique identifier
    phone_number = models.CharField(
        _('phone number'),
        max_length=15,
        unique=True,
        help_text=_('Required. 15 characters or fewer. Digits only.'),
        error_messages={
            'unique': _("A user with that phone number already exists."),
        },
    )
    ROLE_CHOICES = (
        ('rider', 'Rider'),
        ('driver', 'Driver'),
    )
    role = models.CharField(
        max_length=10,
        choices=ROLE_CHOICES,
        default='rider', # Default role can be rider
    )

    USERNAME_FIELD = 'phone_number'
    REQUIRED_FIELDS = ['role'] # Add 'role' to required fields if you want it to be mandatory during creation

    objects = CustomUserManager() # Assign our custom manager

    def __str__(self):
        return self.phone_number
